//! Bone hierarchy, procedural animation and skinning.
//!
//! Bones only rotate about Z (the sagittal plane), which is enough for gait,
//! breathing, jumping and recoil.

use super::surface::model;
use crate::math::{add, cross, mul, rotate_z, sub, unit, V3};
use crate::mesh::Vertex;

pub const JOINT_COUNT: usize = 13;

/// Rest positions: 0 pelvis, 1 chest, 2 neck; 3–5 and 6–8 hip/knee/ankle
/// (left, right); 9–10 and 11–12 shoulder/elbow (left, right).
pub const JOINTS: [V3; JOINT_COUNT] = [
    [0., 0.87, 0.],
    [0., 1.18, 0.],
    [0., 1.51, 0.],
    [0., 0.85, -0.14],
    [0.025, 0.46, -0.15],
    [0.015, 0.12, -0.15],
    [0., 0.85, 0.14],
    [0.025, 0.46, 0.15],
    [0.015, 0.12, 0.15],
    [0., 1.35, -0.28],
    [0.09, 1.08, -0.32],
    [0., 1.35, 0.28],
    [0.09, 1.08, 0.32],
];

/// Parent of each joint; every parent precedes its child, joint 0 is the root.
pub const PARENTS: [usize; JOINT_COUNT] = [0, 0, 1, 0, 3, 4, 0, 6, 7, 1, 9, 1, 11];

// Authored gait keys: contact, down, passing and up. Rotations are radians.
const HIP: [f32; 8] = [-0.48, -0.32, 0., 0.32, 0.48, 0.24, -0.12, -0.38];
const KNEE: [f32; 8] = [0.12, 0.28, 0.65, 0.82, 0.35, 0.08, 0.06, 0.08];

fn key(values: &[f32; 8], phase: f32) -> f32 {
    let frame = phase.rem_euclid(1.) * 8.;
    let i = frame.floor() as usize;
    values[i] + (values[(i + 1) % 8] - values[i]) * (frame - i as f32)
}

/// Local joint rotations for a blend of idle, walk (`movement`), airborne (`air`) and `recoil`.
/// `phase` is the walk cycle position (one cycle per unit).
pub fn joint_rotations(time: f32, phase: f32, movement: f32, air: f32, recoil: f32) -> [f32; JOINT_COUNT] {
    let movement = movement.clamp(0., 1.) * (1. - air.clamp(0., 1.));
    let mut rotations = [0f32; JOINT_COUNT];
    rotations[1] = (time * 2.).sin() * 0.012 - recoil * 0.065;
    rotations[2] = -rotations[1] * 0.6;
    for (hip, knee, ankle, offset) in [(3, 4, 5, 0.), (6, 7, 8, 0.5)] {
        rotations[hip] = key(&HIP, phase + offset) * movement - air * 0.20;
        rotations[knee] = key(&KNEE, phase + offset) * movement + air * 0.48;
        rotations[ankle] = -rotations[knee] * 0.35;
    }
    rotations[9] = key(&HIP, phase) * movement * 0.10 + recoil * 0.10;
    rotations[11] = key(&HIP, phase + 0.5) * movement * 0.10 + recoil * 0.10;
    rotations[10] = -recoil * 0.16;
    rotations[12] = -recoil * 0.16;
    rotations
}

/// Deformed, flat-shaded triangle list for the given animation state.
pub fn pose(time: f32, phase: f32, movement: f32, air: f32, recoil: f32) -> Vec<Vertex> {
    let rotations = joint_rotations(time, phase, movement, air, recoil);
    let mut global = [0f32; JOINT_COUNT];
    let mut positions = JOINTS;
    // Breathing and the vertical bob of the stride.
    positions[0][1] +=
        (time * 2.).sin() * 0.004 + (phase * std::f32::consts::TAU * 2.).cos() * 0.014 * movement;
    for j in 1..JOINT_COUNT {
        let parent = PARENTS[j];
        global[j] = global[parent] + rotations[j];
        positions[j] = add(
            positions[parent],
            rotate_z(sub(JOINTS[j], JOINTS[parent]), global[parent]),
        );
    }
    let model = model();
    let deformed: Vec<_> = model
        .vertices
        .iter()
        .map(|v| {
            let mut p = [0.; 3];
            let mut n = [0.; 3];
            for i in 0..2 {
                let j = v.joints[i];
                p = add(
                    p,
                    mul(
                        add(positions[j], rotate_z(sub(v.position, JOINTS[j]), global[j])),
                        v.weights[i],
                    ),
                );
                n = add(n, mul(rotate_z(v.normal, global[j]), v.weights[i]));
            }
            (p, unit(n))
        })
        .collect();
    let mut result = Vec::with_capacity(model.triangles.len() * 3);
    for triangle in &model.triangles {
        let center = mul(
            triangle
                .iter()
                .map(|&i| model.vertices[i].position)
                .fold([0.; 3], add),
            1. / 3.,
        );
        let material = material_at(center);
        let edge_a = sub(deformed[triangle[1]].0, deformed[triangle[0]].0);
        let edge_b = sub(deformed[triangle[2]].0, deformed[triangle[0]].0);
        let face = unit(cross(edge_a, edge_b));
        for &i in triangle {
            let rest = model.vertices[i].position;
            result.push(Vertex {
                position: deformed[i].0,
                // Partially faceted normals keep an angular, low-poly silhouette.
                normal: unit(add(mul(deformed[i].1, 0.45), mul(face, 0.55))),
                uv: [rest[2] * 1.8 + 0.5, rest[1] * 0.8],
                material,
            });
        }
    }
    result
}

/// Material by body region of the rest pose: boots, helmet, visor, armour, uniform.
fn material_at(center: V3) -> f32 {
    if center[1] < 0.22 {
        12.
    } else if center[1] > 1.67 {
        5.
    } else if center[1] > 1.51 && center[0] > 0.06 {
        11.
    } else if center[1] > 1.0 && center[1] < 1.40 && center[2].abs() < 0.26 {
        5.
    } else {
        4.
    }
}
