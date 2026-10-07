//! The skinned soldier: a continuous triangulated surface ([`surface`]) bound
//! to a 13-bone hierarchical rig ([`rig`]) with two weights per vertex.
//!
//! The rest surface is generated once; animation only deforms its vertices.

mod rig;
mod surface;

pub use rig::{joint_rotations, pose, JOINTS, JOINT_COUNT, PARENTS};
pub use surface::{model, Actor, SkinVertex};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::math::dot;

    #[test]
    fn indexed_skin_is_valid() {
        let m = model();
        assert!(m.vertices.len() > 300);
        assert!(m.triangles.len() < 12000);
        for (j, &parent) in PARENTS.iter().enumerate().skip(1) {
            assert!(parent < j);
        }
        for v in &m.vertices {
            assert!((v.weights.iter().sum::<f32>() - 1.).abs() < 1e-5);
        }
        for t in &m.triangles {
            assert!(t.iter().all(|&i| i < m.vertices.len()));
        }
    }

    #[test]
    fn gait_deforms_surface_and_idle_does_not_walk() {
        let a = pose(0., 0., 1., 0., 0.);
        let b = pose(0., 0.5, 1., 0., 0.);
        assert_eq!(a.len(), b.len());
        assert!(a
            .iter()
            .zip(&b)
            .any(|(a, b)| (a.position[0] - b.position[0]).abs() > 0.15));
        let idle = pose(0., 0., 0., 0., 0.);
        let idle2 = pose(0., 0.5, 0., 0., 0.);
        for (a, b) in idle.iter().zip(&idle2) {
            assert_eq!(a.position, b.position);
        }
        for v in a {
            assert!(v.position.iter().all(|f| f.is_finite()));
            assert!((dot(v.normal, v.normal) - 1.).abs() < 1e-4);
        }
    }
}
