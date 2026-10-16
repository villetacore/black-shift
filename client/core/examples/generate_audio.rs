//! Deterministic original PCM sound effects, generated without recordings.
use std::{f32::consts::TAU, fs, io, path::PathBuf};
fn main() -> io::Result<()> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../assets/audio");
    fs::create_dir_all(&root)?;
    for (index, (name, duration)) in [
        ("smg", 0.24),
        ("shotgun", 0.65),
        ("step", 0.17),
        ("reload", 0.42),
        ("hit", 0.12),
        ("kill", 0.32),
        ("hurt", 0.22),
        ("dash", 0.4),
        ("pulse", 0.55),
        ("relay", 0.7),
        ("warning", 0.5),
        ("victory", 1.3),
    ]
    .into_iter()
    .enumerate()
    {
        let mut seed = 173u32 + index as u32;
        let mut low = 0.;
        let mut pcm = Vec::new();
        for i in 0..(duration * 44100.) as usize {
            let t = i as f32 / 44100.;
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            let noise = (seed >> 8) as f32 / 8388608. - 1.;
            low += (noise - low) * 0.14;
            let tone = |hz: f32| (TAU * hz * t).sin();
            let decay = |rate: f32| (-t * rate).exp();
            let signal = match name {
                "smg" => 0.5 * noise * decay(65.) + 0.8 * low * decay(22.) + 0.45 * tone(95.) * decay(35.),
                "shotgun" => 0.7 * noise * decay(38.) + 1.1 * low * decay(9.) + 0.6 * tone(62.) * decay(14.),
                "step" => 1.3 * low * decay(38.) + 0.22 * tone(85.) * decay(45.),
                "reload" => {
                    noise
                        * (if t > 0.04 {
                            0.55 * (-(t - 0.04) * 85.).exp()
                        } else {
                            0.
                        } + if t > 0.26 {
                            0.4 * (-(t - 0.26) * 70.).exp()
                        } else {
                            0.
                        })
                        + 0.12 * tone(1200.) * decay(25.)
                }
                "hit" => 0.3 * tone(1600.) * decay(55.) + 0.25 * noise * decay(90.),
                "kill" => (0.3 * tone(880.) + 0.22 * tone(1320.)) * decay(12.),
                "hurt" => (0.5 * low + 0.22 * tone(110.)) * decay(20.),
                "dash" => {
                    (0.7 * low + 0.15 * (TAU * (800. * t - 700. * t * t)).sin())
                        * (t * 70.).min(1.)
                        * decay(9.)
                }
                "pulse" => (0.35 * (TAU * (220. * t - 100. * t * t)).sin() + 0.5 * low) * decay(7.),
                "relay" => {
                    let hz = if t < 0.16 {
                        523.25
                    } else if t < 0.32 {
                        659.25
                    } else {
                        783.99
                    };
                    0.32 * tone(hz) * (TAU * t / duration / 2.).sin()
                }
                "warning" => {
                    0.3 * tone(660.)
                        * if t % 0.25 < 0.12 {
                            (TAU * (t % 0.25) / 0.24).sin()
                        } else {
                            0.
                        }
                }
                _ => {
                    (0.18 * tone(523.25) + 0.15 * tone(659.25) + 0.13 * tone(783.99))
                        * (t * 15.).min(1.)
                        * decay(2.5)
                }
            };
            let fade = (t / 0.002).min(1.) * ((duration - t) / 0.015).clamp(0., 1.);
            pcm.extend_from_slice(&((signal.tanh() * fade * 26000.) as i16).to_le_bytes());
        }
        let mut wav = Vec::new();
        wav.extend_from_slice(b"RIFF");
        wav.extend_from_slice(&(36 + pcm.len() as u32).to_le_bytes());
        wav.extend_from_slice(b"WAVEfmt ");
        wav.extend_from_slice(&16u32.to_le_bytes());
        wav.extend_from_slice(&1u16.to_le_bytes());
        wav.extend_from_slice(&1u16.to_le_bytes());
        wav.extend_from_slice(&44100u32.to_le_bytes());
        wav.extend_from_slice(&88200u32.to_le_bytes());
        wav.extend_from_slice(&2u16.to_le_bytes());
        wav.extend_from_slice(&16u16.to_le_bytes());
        wav.extend_from_slice(b"data");
        wav.extend_from_slice(&(pcm.len() as u32).to_le_bytes());
        wav.extend_from_slice(&pcm);
        fs::write(root.join(format!("{name}.wav")), wav)?;
    }
    Ok(())
}
