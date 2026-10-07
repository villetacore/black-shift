//! Procedural 64×64 material tiles.
//!
//! The game renders the painted sheet `assets/textures/painted-materials.png`;
//! this atlas is only used by the asset exporter (`industrial-atlas.tga`).

pub const TILE_SIZE: i32 = 64;
pub const MATERIAL_COUNT: i32 = 16;

/// ARGB colour of material `material` at texel `(x, y)`; coordinates wrap.
pub fn pixel(material: i32, x: i32, y: i32) -> u32 {
    let x = x.rem_euclid(TILE_SIZE);
    let y = y.rem_euclid(TILE_SIZE);
    // Layer broad corrosion patches, coarse stone grain and fine pits.
    // The broad shapes remain readable at the original 64px resolution.
    let hash = |a: i32, b: i32| {
        let n = (a as u32)
            .wrapping_mul(374761393)
            .wrapping_add((b as u32).wrapping_mul(668265263));
        ((n ^ (n >> 13)).wrapping_mul(1274126177) >> 24) as i32
    };
    let broad = |x: i32, y: i32| {
        let a = x / 16;
        let b = y / 16;
        let ease = |t: f32| t * t * (3. - 2. * t);
        let u = ease((x % 16) as f32 / 16.);
        let v = ease((y % 16) as f32 / 16.);
        let top = hash(a, b) as f32 * (1. - u) + hash((a + 1) % 4, b) as f32 * u;
        let bottom = hash(a, (b + 1) % 4) as f32 * (1. - u) + hash((a + 1) % 4, (b + 1) % 4) as f32 * u;
        (top * (1. - v) + bottom * v) as i32 - 128
    };
    let coarse = broad(x, y);
    let grain = hash(x / 2, y / 2) - 128;
    let noise = (hash(x, y) - 128) / 28 + grain / 24 + coarse / 7;
    let bases = [
        [102, 94, 73],
        [143, 133, 103],
        [123, 110, 74],
        [130, 100, 58],
        [101, 107, 71],
        [112, 108, 77],
        [100, 99, 87],
        [160, 125, 94],
        [220, 242, 233],
        [198, 147, 56],
        [25, 29, 28],
        [39, 69, 65],
        [48, 52, 46],
        [83, 76, 54],
        [125, 92, 63],
        [221, 221, 184],
    ];
    let mat = material.rem_euclid(MATERIAL_COUNT) as usize;
    let mut c = bases[mat].map(|v| v + noise);
    let seam = x < 2 || y < 2 || x > 61 || y > 61;
    match mat {
        0 => {
            // Stone floor slabs.
            if seam || y == 32 || (x + if y < 32 { 0 } else { 32 }) % 64 < 2 {
                c = [36 + noise, 33 + noise, 25 + noise];
            }
            if coarse < -45 {
                c = [64 + noise, 65 + noise, 35 + noise];
            }
            if (x + y / 3) % 31 == 0 && grain < 10 {
                c = c.map(|v| v / 2);
            }
        }
        1 => {
            // Concrete masonry.
            if seam || y == 30 || (y < 30 && x == 31) {
                c = c.map(|v| v / 2);
            }
            if y % 31 == 3 {
                c = c.map(|v| v + 18);
            }
            if coarse < -30 && y > 15 {
                c = [96 + noise, 98 + noise, 59 + noise];
            }
        }
        2 | 5 | 6 => {
            // Riveted metal panels.
            if seam || x == 8 || x == 55 {
                c = c.map(|v| v * 2 / 3);
            }
            if (x == 5 || x == 58) && (y == 5 || y == 58) {
                c = [184, 185, 154];
            }
            if (25..38).contains(&x) && (20..46).contains(&y) && y % 5 < 2 {
                c = c.map(|v| v / 2);
            }
            if mat == 2 {
                // Riveted bronze bulkhead with recessed ribbed centre.
                if (14..50).contains(&x) && (9..55).contains(&y) {
                    c = if x % 6 < 3 {
                        [66 + noise, 65 + noise, 49 + noise]
                    } else {
                        [136 + noise, 125 + noise, 88 + noise]
                    };
                }
                if (x - 5).abs() <= 1 || (x - 58).abs() <= 1 {
                    if y % 13 < 3 {
                        c = [46, 39, 26];
                    }
                    if y % 13 == 0 {
                        c = [174, 157, 110];
                    }
                }
            }
            if coarse < -50 && grain < 30 {
                c = [85 + noise, 53 + noise / 2, 29 + noise / 2];
            }
        }
        3 => {
            // Cargo panel with a hazard stripe.
            if (22..43).contains(&y) {
                c = if (x + y) % 20 < 10 {
                    [196, 149, 57]
                } else {
                    [36, 38, 30]
                };
            }
            if seam {
                c = [45, 45, 32];
            }
        }
        4 => {
            // Cloth folds and seams carry the detail; no metal panels on fabric.
            let fold = ((y as f32 * 0.43 + (x as f32 * 0.13).sin() * 1.8).sin() * 7.) as i32;
            c = [84 + noise + fold, 87 + noise + fold, 61 + noise + fold];
            if x == 6 || x == 57 {
                c = c.map(|v| v - 14);
            }
            if y > 38 && y < 55 && x > 17 && x < 45 {
                c = c.map(|v| v - 9);
            }
        }
        7 => {
            if x % 17 < 2 {
                c = c.map(|v| v - 18);
            }
        }
        8 => {
            // Luminous grille.
            if y % 8 < 2 {
                c = [102, 146, 133];
            }
            if seam {
                c = [36, 57, 50];
            }
        }
        9 => {
            if (x + y) % 16 < 7 {
                c = [55, 50, 33];
            }
        }
        11 => {
            // Visor glass gradient.
            c = [35 + y / 3, 57 + y / 2, 58 + y / 2];
            if y % 13 == 0 {
                c = [70, 100, 90];
            }
        }
        13 => {
            // Large ceiling coffers, not a high-frequency checkerboard.
            let edge = x.min(63 - x).min(y.min(63 - y));
            c = match edge {
                0..=2 => [30, 27, 19],
                3..=5 => [139 + noise, 122 + noise, 78 + noise],
                6..=10 => [63 + noise, 57 + noise, 37 + noise],
                _ => [41 + noise, 39 + noise, 29 + noise],
            };
            if edge > 12 && y % 9 < 3 {
                c = c.map(|v| v / 2);
            }
        }
        14 => {
            if (x * 3 + y * 7) % 19 < 3 {
                c = c.map(|v| v - 22);
            }
            if seam {
                c = [51, 47, 36];
            }
        }
        _ => {}
    }
    let c = c.map(|v| v.clamp(0, 255) as u32);
    0xff000000 | c[0] << 16 | c[1] << 8 | c[2]
}
