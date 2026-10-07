//! Low-poly mesh construction. Every mesh is a flat list of triangles
//! (three [`Vertex`] values each) with per-face normals.

mod models;

pub use models::{build, Model};

use crate::math::{cross, sub, V3};
use std::f32::consts::TAU;

/// GPU vertex layout shared with C++ (`BsVertex`).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct Vertex {
    pub position: [f32; 3],
    pub normal: [f32; 3],
    pub uv: [f32; 2],
    /// Material index 0..16, stored as a float vertex attribute.
    pub material: f32,
}

/// Accumulates triangles from simple primitives.
#[derive(Default)]
pub(crate) struct MeshBuilder(pub(crate) Vec<Vertex>);

impl MeshBuilder {
    pub(crate) fn tri(&mut self, a: V3, b: V3, c: V3, uv: [[f32; 2]; 3], material: u8) {
        let n = cross(sub(b, a), sub(c, a));
        let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();
        if len < 1e-8 {
            return;
        }
        let normal = [n[0] / len, n[1] / len, n[2] / len];
        for (position, uv) in [a, b, c].into_iter().zip(uv) {
            self.0.push(Vertex {
                position,
                normal,
                uv,
                material: material as f32,
            });
        }
    }

    pub(crate) fn quad(&mut self, v: [V3; 4], material: u8) {
        self.tri(v[0], v[1], v[2], [[0., 0.], [1., 0.], [1., 1.]], material);
        self.tri(v[0], v[2], v[3], [[0., 0.], [1., 1.], [0., 1.]], material);
    }

    /// Axis-aligned box.
    pub(crate) fn block(&mut self, center: V3, size: V3, material: u8) {
        let [x, y, z] = center;
        let [w, h, d] = size.map(|v| v / 2.);
        let v = [
            [x - w, y - h, z - d],
            [x + w, y - h, z - d],
            [x + w, y + h, z - d],
            [x - w, y + h, z - d],
            [x - w, y - h, z + d],
            [x + w, y - h, z + d],
            [x + w, y + h, z + d],
            [x - w, y + h, z + d],
        ];
        for f in [
            [0, 3, 2, 1],
            [4, 5, 6, 7],
            [0, 4, 7, 3],
            [1, 2, 6, 5],
            [3, 7, 6, 2],
            [0, 1, 5, 4],
        ] {
            self.quad(f.map(|i| v[i]), material);
        }
    }

    /// Vertical prism with an eight-sided, chamfered cross-section; gives
    /// bevelled silhouettes instead of plain boxes. `bottom`/`top` are
    /// half-extents in X and Z.
    pub(crate) fn bevel(&mut self, center: V3, bottom: [f32; 2], top: [f32; 2], height: f32, material: u8) {
        let ring = |r: [f32; 2], y: f32| {
            let [x, z] = r;
            let c = 0.35;
            [
                [x * (1. - c), y, -z],
                [x, y, -z * (1. - c)],
                [x, y, z * (1. - c)],
                [x * (1. - c), y, z],
                [-x * (1. - c), y, z],
                [-x, y, z * (1. - c)],
                [-x, y, -z * (1. - c)],
                [-x * (1. - c), y, -z],
            ]
            .map(|p| [p[0] + center[0], p[1] + center[1], p[2] + center[2]])
        };
        let b = ring(bottom, -height / 2.);
        let t = ring(top, height / 2.);
        for i in 0..8 {
            let j = (i + 1) % 8;
            self.quad([b[i], t[i], t[j], b[j]], material);
            self.tri(
                [center[0], center[1] + height / 2., center[2]],
                t[j],
                t[i],
                [[0.5, 0.5], [1., 0.], [0., 0.]],
                material,
            );
            self.tri(
                [center[0], center[1] - height / 2., center[2]],
                b[i],
                b[j],
                [[0.5, 0.5], [0., 1.], [1., 1.]],
                material,
            );
        }
    }

    /// Eight-sided closed tube along +X starting at `(x, y, z)`.
    pub(crate) fn tube_x(&mut self, x: f32, y: f32, z: f32, length: f32, radius: f32, material: u8) {
        for i in 0..8 {
            let a = i as f32 * TAU / 8.;
            let b = (i + 1) as f32 * TAU / 8.;
            let p = [x, y + a.cos() * radius, z + a.sin() * radius];
            let q = [x, y + b.cos() * radius, z + b.sin() * radius];
            self.quad(
                [p, q, [x + length, q[1], q[2]], [x + length, p[1], p[2]]],
                material,
            );
            self.tri([x, y, z], q, p, [[0.5, 0.5], [0., 0.], [1., 1.]], material);
            self.tri(
                [x + length, y, z],
                [x + length, p[1], p[2]],
                [x + length, q[1], q[2]],
                [[0.5, 0.5], [1., 1.], [0., 0.]],
                material,
            );
        }
    }

    /// The pulse carbine, scaled and translated into place.
    pub(crate) fn rifle(&mut self, offset: V3, scale: f32) {
        let start = self.0.len();
        self.bevel([0.15, 0., 0.], [0.28, 0.065], [0.28, 0.06], 0.16, 6);
        self.block([-0.22, -0.015, 0.], [0.28, 0.12, 0.08], 4);
        self.block([0.05, -0.14, 0.], [0.10, 0.22, 0.07], 6);
        self.block([0.28, -0.13, 0.], [0.12, 0.19, 0.08], 12);
        self.tube_x(0.39, 0.02, 0., 0.35, 0.034, 6);
        self.tube_x(0.69, 0.02, 0., 0.10, 0.048, 12);
        self.block([0.32, 0.11, 0.], [0.24, 0.026, 0.035], 12);
        self.block([0.51, 0.075, 0.], [0.025, 0.08, 0.018], 12);
        self.block([0.12, 0.043, 0.067], [0.07, 0.025, 0.003], 8);
        for v in &mut self.0[start..] {
            for (i, o) in offset.iter().enumerate() {
                v.position[i] = v.position[i] * scale + o;
            }
        }
    }
}

mod expansion;
