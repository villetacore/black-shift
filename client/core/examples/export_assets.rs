//! Export the same geometry and atlas used by the native client.
use blackshift_core::actor;
use blackshift_core::atlas;
use blackshift_core::mesh::{build, Model};
use std::{fs, io::Write, path::PathBuf};

fn main() -> std::io::Result<()> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets");
    fs::create_dir_all(root.join("models"))?;
    fs::create_dir_all(root.join("textures"))?;
    let mut tga = vec![0u8; 18];
    tga[2] = 2;
    tga[12..14].copy_from_slice(&256u16.to_le_bytes());
    tga[14..16].copy_from_slice(&256u16.to_le_bytes());
    tga[16] = 32;
    tga[17] = 0x28;
    for y in 0..256 {
        for x in 0..256 {
            let pixel = atlas::pixel((y / 64) * 4 + x / 64, x % 64, y % 64);
            tga.extend_from_slice(&pixel.to_le_bytes());
        }
    }
    fs::write(root.join("textures/industrial-atlas.tga"), tga)?;
    fs::write(
        root.join("models/industrial.mtl"),
        "newmtl industrial\nKd 1 1 1\nmap_Kd ../textures/foundry-materials.png\n",
    )?;
    for (name, model) in [
        ("soldier", Model::Soldier),
        ("drone", Model::Drone),
        ("turret", Model::TurretBase),
        ("reactor", Model::Reactor),
        ("carbine", Model::Carbine),
        ("crate", Model::Crate),
        ("barrel", Model::Barrel),
        ("vent", Model::Vent),
        ("cabinet", Model::Cabinet),
        ("pallet", Model::Pallet),
        ("console", Model::Console),
        ("generator", Model::Generator),
        ("tank", Model::Tank),
        ("pump", Model::Pump),
        ("cable-spool", Model::CableSpool),
        ("bollard", Model::Bollard),
        ("lamp", Model::Lamp),
        ("barricade", Model::Barricade),
        ("fan", Model::Fan),
        ("shotgun", Model::Shotgun),
        ("smg", Model::Smg),
        ("warden-gear", Model::WardenGear),
        ("ranger-gear", Model::RangerGear),
    ] {
        let mut vertices = build(model);
        // The soldier is exported in its skinned rest pose; the turret includes its head.
        if model == Model::Soldier {
            vertices = actor::pose(0., 0., 0., 0., 0.);
        }
        if model == Model::TurretBase {
            vertices.extend(build(Model::TurretHead).into_iter().map(|mut v| {
                v.position[1] += 1.4;
                v
            }));
        }
        let mut file = fs::File::create(root.join(format!("models/{name}.obj")))?;
        writeln!(
            file,
            "# Original Black Shift mesh; Y up; metres\nmtllib industrial.mtl\no {name}\nusemtl industrial"
        )?;
        for v in &vertices {
            writeln!(file, "v {} {} {}", v.position[0], v.position[1], v.position[2])?;
            let mat = v.material as i32;
            let u = ((mat % 4) as f32 * 64.0 + 0.5 + v.uv[0].clamp(0.0, 1.0) * 63.0) / 256.0;
            let t = ((mat / 4) as f32 * 64.0 + 0.5 + v.uv[1].clamp(0.0, 1.0) * 63.0) / 256.0;
            writeln!(file, "vt {u} {}", 1.0 - t)?;
            writeln!(file, "vn {} {} {}", v.normal[0], v.normal[1], v.normal[2])?;
        }
        for i in (1..=vertices.len()).step_by(3) {
            writeln!(file, "f {0}/{0}/{0} {1}/{1}/{1} {2}/{2}/{2}", i, i + 1, i + 2)?;
        }
        println!("{name}: {} triangles", vertices.len() / 3);
    }
    export_rig(&root)?;
    export_water(&root)?;
    Ok(())
}

fn export_rig(root: &std::path::Path) -> std::io::Result<()> {
    use actor::{joint_rotations, model, pose, JOINTS, JOINT_COUNT, PARENTS};
    fn skeleton(f: &mut fs::File, rotations: [f32; JOINT_COUNT], frame: usize) -> std::io::Result<()> {
        writeln!(f, "time {frame}")?;
        for j in 0..JOINT_COUNT {
            let p = if j == 0 {
                JOINTS[j]
            } else {
                std::array::from_fn(|i| JOINTS[j][i] - JOINTS[PARENTS[j]][i])
            };
            writeln!(f, "{j} {} {} {} 0 0 {}", p[0], p[1], p[2], rotations[j])?;
        }
        Ok(())
    }
    for clip in ["reference", "idle", "walk", "jump", "fire"] {
        let mut f = fs::File::create(root.join(format!("models/soldier-{clip}.smd")))?;
        writeln!(f, "version 1\nnodes")?;
        for (j, parent) in PARENTS.iter().enumerate() {
            writeln!(f, "{j} \"bone_{j}\" {}", if j == 0 { -1 } else { *parent as i32 })?;
        }
        writeln!(f, "end\nskeleton")?;
        let count = if clip == "reference" { 1 } else { 33 };
        for frame in 0..count {
            let phase = frame as f32 / 32.;
            let r = joint_rotations(
                phase * 2.,
                phase,
                if clip == "walk" { 1. } else { 0. },
                if clip == "jump" {
                    (phase * std::f32::consts::PI).sin()
                } else {
                    0.
                },
                if clip == "fire" { (-phase * 8.).exp() } else { 0. },
            );
            skeleton(&mut f, r, frame)?;
        }
        writeln!(f, "end")?;
        if clip == "reference" {
            writeln!(f, "triangles")?;
            let vertices = pose(0., 0., 0., 0., 0.);
            for (face, triangle) in model().triangles.iter().enumerate() {
                writeln!(f, "../textures/painted-materials.png")?;
                for (corner, &index) in triangle.iter().enumerate() {
                    let v = vertices[face * 3 + corner];
                    let skin = &model().vertices[index];
                    let m = v.material as i32;
                    let uv = [
                        ((m % 4) as f32 + v.uv[0].rem_euclid(1.)) / 4.,
                        1. - ((m / 4) as f32 + v.uv[1].rem_euclid(1.)) / 4.,
                    ];
                    writeln!(
                        f,
                        "{} {} {} {} {} {} {} {} {} 2 {} {} {} {}",
                        skin.joints[0],
                        v.position[0],
                        v.position[1],
                        v.position[2],
                        v.normal[0],
                        v.normal[1],
                        v.normal[2],
                        uv[0],
                        uv[1],
                        skin.joints[0],
                        skin.weights[0],
                        skin.joints[1],
                        skin.weights[1]
                    )?;
                }
            }
            writeln!(f, "end")?;
        }
    }
    Ok(())
}

// Seamless 128px water material, exported as uncompressed BMP for Qt's built-in decoder.
fn export_water(root: &std::path::Path) -> std::io::Result<()> {
    let side = 128u32;
    let bytes = side * side * 4;
    let mut bmp = Vec::new();
    bmp.extend_from_slice(b"BM");
    bmp.extend_from_slice(&(54 + bytes).to_le_bytes());
    bmp.extend_from_slice(&[0; 4]);
    bmp.extend_from_slice(&54u32.to_le_bytes());
    bmp.extend_from_slice(&40u32.to_le_bytes());
    bmp.extend_from_slice(&side.to_le_bytes());
    bmp.extend_from_slice(&side.to_le_bytes());
    bmp.extend_from_slice(&1u16.to_le_bytes());
    bmp.extend_from_slice(&32u16.to_le_bytes());
    bmp.extend_from_slice(&[0; 24]);
    for y in 0..side {
        for x in 0..side {
            let u = x as f32 / side as f32 * std::f32::consts::TAU;
            let v = y as f32 / side as f32 * std::f32::consts::TAU;
            let wave = (u * 3. + (v * 2.).sin()).sin() * (v * 4. + u.cos()).cos();
            let grain = ((x * 37 + y * 71 + x * y * 13) % 17) as f32;
            let value = (100. + wave * 55. + grain) as u8;
            bmp.extend_from_slice(&[value, value, value, 255]);
        }
    }
    fs::write(root.join("textures/cooling-water.bmp"), bmp)
}
