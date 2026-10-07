//! The game's rigid models. Material indices refer to the 4×4 material sheet.

use super::{MeshBuilder, Vertex};

/// Model identifiers; the values are part of the C ABI (`BsModel`).
#[repr(i32)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Model {
    /// Unit cube centred on the origin; used for effects and markers.
    Cube = 0,
    /// Rigid soldier used for OBJ export (the game renders the skinned actor).
    Soldier = 1,
    /// Single leg with its origin at the hip.
    Leg = 2,
    Drone = 3,
    TurretBase = 4,
    TurretHead = 5,
    Reactor = 6,
    /// First-person carbine with gloved hands.
    Carbine = 7,
    Crate = 8,
    Pipe = 9,
    Barrel = 10,
    Vent = 11,
    Cabinet = 12,
    Pallet = 13,
    Console = 14,
    Generator = 15,
    Tank = 16,
    Pump = 17,
    CableSpool = 18,
    Bollard = 19,
    Lamp = 20,
    Barricade = 21,
    Fan = 22,
    Shotgun = 23,
    Smg = 24,
    WardenGear = 25,
    RangerGear = 26,
}

impl Model {
    pub const ALL: [Model; 27] = [
        Model::Cube,
        Model::Soldier,
        Model::Leg,
        Model::Drone,
        Model::TurretBase,
        Model::TurretHead,
        Model::Reactor,
        Model::Carbine,
        Model::Crate,
        Model::Pipe,
        Model::Barrel,
        Model::Vent,
        Model::Cabinet,
        Model::Pallet,
        Model::Console,
        Model::Generator,
        Model::Tank,
        Model::Pump,
        Model::CableSpool,
        Model::Bollard,
        Model::Lamp,
        Model::Barricade,
        Model::Fan,
        Model::Shotgun,
        Model::Smg,
        Model::WardenGear,
        Model::RangerGear,
    ];

    pub fn from_raw(raw: i32) -> Option<Model> {
        Model::ALL.get(usize::try_from(raw).ok()?).copied()
    }
}

pub fn build(model: Model) -> Vec<Vertex> {
    let mut m = MeshBuilder::default();
    match model {
        Model::Cube => m.block([0., 0., 0.], [1., 1., 1.], 1),
        Model::Soldier => {
            // Pelvis, armoured torso, rounded helmet, visor, arms and rifle.
            m.bevel([0., 0.88, 0.], [0.16, 0.20], [0.16, 0.23], 0.22, 4);
            m.bevel([0., 1.19, 0.], [0.15, 0.21], [0.19, 0.27], 0.44, 5);
            m.block([0.175, 1.19, 0.], [0.055, 0.31, 0.38], 5);
            for z in [-0.15, 0., 0.15] {
                m.block([0.216, 1.1, z], [0.06, 0.13, 0.10], 4);
            }
            m.block([-0.21, 1.16, 0.], [0.19, 0.29, 0.32], 4);
            m.bevel([0., 1.45, 0.], [0.07, 0.08], [0.08, 0.08], 0.10, 7);
            m.bevel([0.01, 1.60, 0.], [0.14, 0.13], [0.15, 0.14], 0.22, 7);
            m.bevel([-0.015, 1.72, 0.], [0.18, 0.18], [0.12, 0.13], 0.19, 5);
            m.block([0.157, 1.63, 0.], [0.025, 0.085, 0.26], 11);
            m.block([0.176, 1.646, 0.], [0.008, 0.014, 0.21], 8);
            for z in [-0.31, 0.31] {
                m.bevel([0., 1.34, z], [0.13, 0.10], [0.15, 0.13], 0.20, 5);
                m.bevel([0.055, 1.15, z], [0.10, 0.085], [0.115, 0.10], 0.25, 4);
                m.bevel([0.225, 1.06, z * 0.68], [0.18, 0.08], [0.16, 0.08], 0.15, 5);
                m.bevel([0.39, 1.055, z * 0.56], [0.07, 0.06], [0.06, 0.06], 0.13, 7);
                m.block([0.005, 1.37, z + z.signum() * 0.11], [0.15, 0.08, 0.01], 8);
            }
            m.rifle([0.48, 1.1, 0.12], 0.78);
        }
        Model::Leg => {
            m.bevel([0., -0.18, 0.], [0.105, 0.095], [0.13, 0.11], 0.36, 4);
            m.bevel([0.025, -0.40, 0.], [0.09, 0.09], [0.11, 0.105], 0.15, 5);
            m.bevel([0., -0.57, 0.], [0.09, 0.085], [0.10, 0.09], 0.26, 4);
            m.bevel([0.055, -0.75, 0.], [0.175, 0.11], [0.125, 0.10], 0.18, 12);
        }
        Model::Drone => {
            // Tracked support drone with wheels, sensor and gun.
            m.bevel([0., 0.31, 0.], [0.37, 0.31], [0.25, 0.23], 0.29, 5);
            for z in [-0.32, 0.32] {
                m.block([0., 0.16, z], [0.78, 0.22, 0.13], 12);
                for x in [-0.25, 0., 0.25] {
                    m.bevel([x, 0.17, z], [0.08, 0.085], [0.07, 0.07], 0.13, 6);
                }
            }
            m.bevel([0.08, 0.54, 0.], [0.18, 0.17], [0.13, 0.13], 0.19, 5);
            m.block([0.23, 0.55, 0.], [0.035, 0.075, 0.20], 8);
            m.tube_x(0.23, 0.40, 0.18, 0.34, 0.04, 6);
            m.block([-0.23, 0.58, -0.18], [0.024, 0.40, 0.024], 6);
        }
        Model::TurretBase => {
            m.bevel([0., 0.16, 0.], [0.55, 0.55], [0.45, 0.45], 0.32, 2);
            m.bevel([0., 0.64, 0.], [0.31, 0.31], [0.22, 0.22], 0.70, 5);
            m.bevel([0., 1.06, 0.], [0.38, 0.38], [0.36, 0.36], 0.19, 3);
            for z in [-0.28, 0.28] {
                m.block([0., 0.62, z], [0.15, 0.42, 0.02], 8);
            }
        }
        Model::TurretHead => {
            // Rotates independently of the base; twin barrels.
            m.bevel([0., 0., 0.], [0.31, 0.32], [0.24, 0.27], 0.31, 5);
            for z in [-0.21, 0.21] {
                m.tube_x(0.17, -0.02, z, 0.72, 0.075, 6);
                m.tube_x(0.82, -0.02, z, 0.12, 0.095, 12);
            }
            m.block([0.29, 0.09, 0.], [0.035, 0.06, 0.18], 8);
            m.bevel([-0.19, 0.24, 0.], [0.08, 0.12], [0.05, 0.11], 0.17, 6);
        }
        Model::Reactor => {
            // Team core: cage, glowing central column, armoured cap.
            m.bevel([0., 0.14, 0.], [0.62, 0.62], [0.51, 0.51], 0.28, 3);
            m.bevel([0., 0.95, 0.], [0.21, 0.21], [0.24, 0.24], 1.35, 8);
            for x in [-0.39, 0.39] {
                for z in [-0.39, 0.39] {
                    m.bevel([x, 0.97, z], [0.08, 0.08], [0.11, 0.11], 1.62, 2);
                }
            }
            for y in [0.38, 0.87, 1.38] {
                m.bevel([0., y, 0.], [0.44, 0.44], [0.44, 0.44], 0.10, 6);
            }
            m.bevel([0., 1.82, 0.], [0.51, 0.51], [0.36, 0.36], 0.30, 5);
        }
        Model::Carbine => {
            m.rifle([0., 0., 0.], 1.0);
            m.bevel([-0.09, -0.20, 0.12], [0.09, 0.075], [0.10, 0.09], 0.20, 7);
            m.bevel([-0.25, -0.32, 0.18], [0.20, 0.09], [0.14, 0.085], 0.17, 4);
            m.bevel([0.36, -0.115, -0.04], [0.075, 0.105], [0.08, 0.11], 0.10, 7);
            m.bevel([0.14, -0.25, -0.16], [0.24, 0.085], [0.17, 0.085], 0.17, 4);
        }
        Model::Crate => {
            m.bevel([0., 0., 0.], [0.5, 0.5], [0.5, 0.5], 1.0, 14);
            for y in [-0.39, 0.39] {
                m.block([0., y, 0.], [1.02, 0.10, 1.02], 2);
            }
            for z in [-0.39, 0.39] {
                m.block([0., 0., z], [1.02, 1., 0.08], 2);
            }
        }
        Model::Pipe => m.tube_x(0., 0., 0., 1., 0.12, 14),
        Model::Barrel => {
            m.bevel([0., 0., 0.], [0.43, 0.43], [0.43, 0.43], 1.0, 14);
            for y in [-0.43, 0., 0.43] {
                m.bevel([0., y, 0.], [0.46, 0.46], [0.46, 0.46], 0.07, 12);
            }
            m.bevel([0.16, 0.49, 0.08], [0.06, 0.06], [0.06, 0.06], 0.02, 6);
        }
        Model::Vent => {
            m.block([0., 0., 0.], [1., 1., 1.], 12);
            for y in [-0.35, -0.18, 0., 0.18, 0.35] {
                m.block([0., y, 0.51], [0.82, 0.055, 0.04], 2);
            }
            m.block([0., 0.51, 0.], [0.7, 0.04, 0.7], 6);
        }
        Model::Cabinet => {
            m.bevel([0., 0., 0.], [0.5, 0.5], [0.5, 0.5], 1., 5);
            m.block([0., 0., 0.5], [0.86, 0.87, 0.025], 12);
            m.block([0.28, 0., 0.53], [0.045, 0.2, 0.05], 2);
            m.block([-0.16, 0.23, 0.53], [0.2, 0.14, 0.025], 8);
            for x in [-0.23, -0.07, 0.09] {
                m.block([x, -0.22, 0.53], [0.065, 0.065, 0.025], 3);
            }
        }
        other => return super::expansion::build(other),
    }
    m.0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_model_is_triangulated_and_has_unit_normals() {
        for model in Model::ALL {
            let vertices = build(model);
            assert!(!vertices.is_empty());
            assert_eq!(vertices.len() % 3, 0);
            for v in vertices {
                assert!(v.position.iter().all(|f| f.is_finite()));
                let len = v.normal.iter().map(|v| v * v).sum::<f32>();
                assert!((len - 1.).abs() < 1e-4);
                assert!((0.0..16.0).contains(&v.material));
            }
        }
    }

    #[test]
    fn model_ids_round_trip() {
        for model in Model::ALL {
            assert_eq!(Model::from_raw(model as i32), Some(model));
        }
        assert_eq!(Model::from_raw(-1), None);
        assert_eq!(Model::from_raw(Model::ALL.len() as i32), None);
    }

    #[test]
    fn soldier_has_volume_and_correct_scale() {
        let v = build(Model::Soldier);
        for axis in 0..3 {
            let min = v.iter().map(|v| v.position[axis]).fold(f32::INFINITY, f32::min);
            let max = v
                .iter()
                .map(|v| v.position[axis])
                .fold(f32::NEG_INFINITY, f32::max);
            assert!(max - min > 0.5);
        }
        assert!(v.iter().all(|v| v.position[1] < 1.9));
    }
}
