//! C ABI used by the Qt client. Keep in sync with `include/blackshift_core.h`.
//!
//! Every function validates its arguments and returns 0 instead of writing
//! when a buffer is missing or too small.

use crate::actor;
use crate::atlas;
use crate::mesh::{build, Model, Vertex};

fn model_vertices(model: i32) -> Vec<Vertex> {
    Model::from_raw(model).map(build).unwrap_or_default()
}

/// Number of vertices of a rigid model (`BsModel`), or 0 for an unknown id.
#[no_mangle]
pub extern "C" fn bs_mesh_vertex_count(model: i32) -> i32 {
    model_vertices(model).len() as i32
}

/// Writes a rigid model's vertices; returns the count written.
///
/// # Safety
/// `out` must point to `capacity` writable, aligned `Vertex` values that do not alias.
#[no_mangle]
pub unsafe extern "C" fn bs_mesh_vertices(model: i32, out: *mut Vertex, capacity: i32) -> i32 {
    if out.is_null() || capacity < 0 {
        return 0;
    }
    write(&model_vertices(model), out, capacity)
}

/// ARGB texel of the procedural material atlas.
#[no_mangle]
pub extern "C" fn bs_atlas_pixel(material: i32, x: i32, y: i32) -> u32 {
    atlas::pixel(material, x, y)
}

/// Number of vertices produced by [`bs_actor_pose`].
#[no_mangle]
pub extern "C" fn bs_actor_vertex_count() -> i32 {
    (actor::model().triangles.len() * 3) as i32
}

/// Writes the skinned soldier in the given animation state; returns the count written.
///
/// # Safety
/// `out` must point to at least `capacity` writable, aligned `Vertex` values.
#[no_mangle]
pub unsafe extern "C" fn bs_actor_pose(
    time: f32,
    phase: f32,
    movement: f32,
    air: f32,
    recoil: f32,
    out: *mut Vertex,
    capacity: i32,
) -> i32 {
    if out.is_null()
        || capacity < bs_actor_vertex_count()
        || ![time, phase, movement, air, recoil].iter().all(|v| v.is_finite())
    {
        return 0;
    }
    write(&actor::pose(time, phase, movement, air, recoil), out, capacity)
}

unsafe fn write(data: &[Vertex], out: *mut Vertex, capacity: i32) -> i32 {
    if data.len() > capacity as usize {
        return 0;
    }
    std::ptr::copy_nonoverlapping(data.as_ptr(), out, data.len());
    data.len() as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn export_does_not_overwrite_short_buffers() {
        let mut v = Vertex::default();
        assert_eq!(unsafe { bs_mesh_vertices(Model::Soldier as i32, &mut v, 1) }, 0);
        assert_eq!(v.position, [0.; 3]);
        assert_eq!(unsafe { bs_actor_pose(0., 0., 0., 0., 0., &mut v, 1) }, 0);
    }

    #[test]
    fn unknown_models_are_empty() {
        assert_eq!(bs_mesh_vertex_count(-1), 0);
        assert_eq!(bs_mesh_vertex_count(Model::ALL.len() as i32), 0);
    }
}
