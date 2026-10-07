//! Minimal 3-component vector helpers.

pub type V3 = [f32; 3];

pub fn add(a: V3, b: V3) -> V3 {
    std::array::from_fn(|i| a[i] + b[i])
}

pub fn sub(a: V3, b: V3) -> V3 {
    std::array::from_fn(|i| a[i] - b[i])
}

pub fn mul(a: V3, s: f32) -> V3 {
    a.map(|v| v * s)
}

pub fn dot(a: V3, b: V3) -> f32 {
    a.iter().zip(b).map(|(a, b)| a * b).sum()
}

pub fn cross(a: V3, b: V3) -> V3 {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

/// Unit vector; near-zero input yields a near-zero result instead of NaN.
pub fn unit(a: V3) -> V3 {
    mul(a, 1.0 / dot(a, a).sqrt().max(0.00001))
}

/// Rotation about the Z axis (the rig's bending axis).
pub fn rotate_z(a: V3, angle: f32) -> V3 {
    let (s, c) = angle.sin_cos();
    [a[0] * c - a[1] * s, a[0] * s + a[1] * c, a[2]]
}
