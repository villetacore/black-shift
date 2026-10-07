//! Black Shift client core: procedural low-poly models, the skinned soldier
//! and the fallback material atlas.
//!
//! The Qt client links this crate as a static library through the C ABI in
//! [`ffi`] (declared in `include/blackshift_core.h`). The `export_assets`
//! example uses the Rust API directly to write OBJ/SMD/TGA files.
//!
//! Conventions: metres, Y up, models face +X.

pub mod actor;
pub mod atlas;
pub mod ffi;
pub mod math;
pub mod mesh;
