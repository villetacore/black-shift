//! Soldier rest surface: a signed distance field of blended ellipsoids and
//! capsules, polygonised with marching tetrahedra and welded into an indexed
//! mesh. Each vertex is bound to its two nearest bones.

use super::rig::JOINTS;
use crate::math::{add, cross, dot, mul, sub, unit, V3};
use std::{collections::HashMap, sync::OnceLock};

#[derive(Clone)]
pub struct SkinVertex {
    pub position: V3,
    pub normal: V3,
    pub joints: [usize; 2],
    pub weights: [f32; 2],
}

pub struct Actor {
    pub vertices: Vec<SkinVertex>,
    pub triangles: Vec<[usize; 3]>,
}

/// The shared rest mesh, generated on first use.
pub fn model() -> &'static Actor {
    static MODEL: OnceLock<Actor> = OnceLock::new();
    MODEL.get_or_init(generate)
}

fn ellipsoid(p: V3, c: V3, radii: V3) -> f32 {
    let d = sub(p, c);
    let q: V3 = std::array::from_fn(|i| d[i] / radii[i]);
    (dot(q, q).sqrt() - 1.) * radii.into_iter().fold(f32::INFINITY, f32::min)
}

fn segment(p: V3, a: V3, b: V3) -> f32 {
    let d = sub(b, a);
    let t = (dot(sub(p, a), d) / dot(d, d)).clamp(0., 1.);
    let q = sub(p, add(a, mul(d, t)));
    dot(q, q).sqrt()
}

fn smooth_min(a: f32, b: f32) -> f32 {
    let h = ((0.055 - (a - b).abs()) / 0.055).max(0.);
    a.min(b) - h * h * 0.055 * 0.25
}

/// Negative inside the body: torso, pelvis, neck, head, helmet, legs, arms, boots and hands.
fn field(p: V3) -> f32 {
    let mut d = ellipsoid(p, [0., 1.16, 0.], [0.18, 0.30, 0.255]);
    for (c, r) in [
        ([0., 0.87, 0.], [0.17, 0.17, 0.24]),
        ([0., 1.46, 0.], [0.085, 0.13, 0.09]),
        ([0.025, 1.62, 0.], [0.13, 0.17, 0.13]),
        ([-0.015, 1.70, 0.], [0.15, 0.13, 0.155]),
    ] {
        d = smooth_min(d, ellipsoid(p, c, r));
    }
    for s in [-1., 1.] {
        for (a, b, r) in [
            ([0., 0.86, s * 0.14], [0.025, 0.46, s * 0.15], 0.115),
            ([0.025, 0.46, s * 0.15], [0.015, 0.13, s * 0.15], 0.085),
            ([0., 1.35, s * 0.245], [0.09, 1.08, s * 0.32], 0.105),
            ([0.09, 1.08, s * 0.32], [0.34, 1.12, s * 0.13], 0.075),
        ] {
            d = smooth_min(d, segment(p, a, b) - r);
        }
        d = smooth_min(d, ellipsoid(p, [0.08, 0.10, s * 0.15], [0.19, 0.095, 0.105]));
        d = smooth_min(d, ellipsoid(p, [0.34, 1.12, s * 0.13], [0.09, 0.075, 0.07]));
    }
    d
}

fn normal(p: V3) -> V3 {
    unit(std::array::from_fn(|i| {
        let mut a = p;
        let mut b = p;
        a[i] += 0.002;
        b[i] -= 0.002;
        field(a) - field(b)
    }))
}

/// The two nearest bones among those plausible for this body region, inverse-distance weighted.
fn weights(p: V3) -> ([usize; 2], [f32; 2]) {
    let candidates: &[usize] = if p[1] < 0.89 {
        if p[2] < 0. {
            &[0, 3, 4, 5]
        } else {
            &[0, 6, 7, 8]
        }
    } else if p[2].abs() > 0.235 || (p[0] > 0.20 && p[1] < 1.3) {
        if p[2] < 0. {
            &[1, 9, 10]
        } else {
            &[1, 11, 12]
        }
    } else if p[1] > 1.43 {
        &[1, 2]
    } else {
        &[0, 1]
    };
    let mut distances: Vec<_> = candidates
        .iter()
        .map(|&j| {
            // Bone segments run from a joint to its child joint, or to the limb tip.
            let end = match j {
                0 => JOINTS[1],
                1 => JOINTS[2],
                2 => [0., 1.78, 0.],
                3 => JOINTS[4],
                4 => JOINTS[5],
                5 => [0.23, 0.1, -0.15],
                6 => JOINTS[7],
                7 => JOINTS[8],
                8 => [0.23, 0.1, 0.15],
                9 => JOINTS[10],
                10 => [0.34, 1.12, -0.13],
                11 => JOINTS[12],
                _ => [0.34, 1.12, 0.13],
            };
            (segment(p, JOINTS[j], end).max(0.015), j)
        })
        .collect();
    distances.sort_by(|a, b| a.0.total_cmp(&b.0));
    let a = 1. / distances[0].0.powi(4);
    let b = 1. / distances[1].0.powi(4);
    ([distances[0].1, distances[1].1], [a / (a + b), b / (a + b)])
}

fn generate() -> Actor {
    const CELL: f32 = 0.09;
    const ORIGIN: V3 = [-0.32, -0.04, -0.54];
    const CELLS: [i32; 3] = [10, 22, 12];
    const CORNERS: [[i32; 3]; 8] = [
        [0, 0, 0],
        [1, 0, 0],
        [1, 1, 0],
        [0, 1, 0],
        [0, 0, 1],
        [1, 0, 1],
        [1, 1, 1],
        [0, 1, 1],
    ];
    // Six tetrahedra sharing the cube diagonal 0–6.
    const TETRAHEDRA: [[usize; 4]; 6] = [
        [0, 5, 1, 6],
        [0, 1, 2, 6],
        [0, 2, 3, 6],
        [0, 3, 7, 6],
        [0, 7, 4, 6],
        [0, 4, 5, 6],
    ];

    let mut actor = Actor {
        vertices: Vec::new(),
        triangles: Vec::new(),
    };
    let mut welded = HashMap::<[i32; 3], usize>::new();
    for x in 0..CELLS[0] {
        for y in 0..CELLS[1] {
            for z in 0..CELLS[2] {
                let p: [V3; 8] = CORNERS.map(|c| {
                    [
                        ORIGIN[0] + (x + c[0]) as f32 * CELL,
                        ORIGIN[1] + (y + c[1]) as f32 * CELL,
                        ORIGIN[2] + (z + c[2]) as f32 * CELL,
                    ]
                });
                let f = p.map(field);
                for tet in TETRAHEDRA {
                    let mut cuts = Vec::new();
                    for [a, b] in [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]] {
                        let a = tet[a];
                        let b = tet[b];
                        if (f[a] < 0.) != (f[b] < 0.) {
                            cuts.push(add(p[a], mul(sub(p[b], p[a]), f[a] / (f[a] - f[b]))));
                        }
                    }
                    if cuts.len() < 3 {
                        continue;
                    }
                    // Order the cut points around their centre so the polygon is convex.
                    let center = mul(cuts.iter().copied().fold([0.; 3], add), 1. / cuts.len() as f32);
                    let n = normal(center);
                    let u = unit(sub(cuts[0], center));
                    let v = cross(n, u);
                    cuts.sort_by(|a, b| {
                        let a = sub(*a, center);
                        let b = sub(*b, center);
                        dot(a, v).atan2(dot(a, u)).total_cmp(&dot(b, v).atan2(dot(b, u)))
                    });
                    let ids: Vec<_> = cuts
                        .iter()
                        .map(|&position| {
                            let key = position.map(|c| (c * 100000.).round() as i32);
                            *welded.entry(key).or_insert_with(|| {
                                let (joints, weights) = weights(position);
                                let id = actor.vertices.len();
                                actor.vertices.push(SkinVertex {
                                    position,
                                    normal: normal(position),
                                    joints,
                                    weights,
                                });
                                id
                            })
                        })
                        .collect();
                    for i in 1..ids.len() - 1 {
                        actor.triangles.push([ids[0], ids[i], ids[i + 1]]);
                    }
                }
            }
        }
    }
    actor
}
