#pragma once
#include <reshade.hpp>
#include "source_camera.h"
#include <algorithm>
#include <cmath>
#include <cstdint>

// Own capture of the largest world-camera depth pass. Clear order can differ
// between Source maps; a fixed clear number also captures viewmodels on some maps.
namespace source_depth {
using namespace reshade::api;
inline device* owner=nullptr;
inline resource texture{};
inline resource_view srv{},current{};
inline uint32_t width=0,height=0,expectedWidth=0,expectedHeight=0;
inline uint64_t score=0,best=0,copied=0;
inline double eyeX=0,eyeY=0,eyeZ=0;
inline float fov=104.8f;
inline bool enabled=false,copying=false;
static_assert(RESHADE_API_VERSION==20,"Revalidate capture ABI for another SDK");
inline resource from_view(device* d,resource_view v) {
    resource result{};
#if defined(__i386__) && defined(__MINGW32__)
    using Fn=void(__thiscall*)(device*,resource*,resource_view);
    auto table=*reinterpret_cast<void***>(d);
    reinterpret_cast<Fn>(table[13])(d,&result,v);
#else
    result=d->get_resource_from_view(v);
#endif
    return result;
}
inline resource_desc description(device* d,resource r) {
    resource_desc result{};
#if defined(__i386__) && defined(__MINGW32__)
    using Fn=void(__thiscall*)(device*,resource_desc*,resource);
    auto table=*reinterpret_cast<void***>(d);
    reinterpret_cast<Fn>(table[10])(d,&result,r);
#else
    result=d->get_resource_desc(r);
#endif
    return result;
}
inline void destroy(device* d) {
    if(owner!=d)return;
    if(srv.handle)d->destroy_resource_view(srv);
    if(texture.handle)d->destroy_resource(texture);
    texture={};srv={};current={};owner=nullptr;width=height=0;score=best=copied=0;
}
inline void capture(command_list* cmd,resource_view view) {
    if(!enabled || copying || !view.handle || score<256 || score<=best)return;
    auto dev=cmd->get_device();
    if(dev->get_api()!=device_api::d3d9)return;
    auto source=from_view(dev,view);if(!source.handle)return;
    auto desc=description(dev,source);
    // Retain Generic Depth as the fallback for unsupported MSAA resources.
    if(desc.type!=resource_type::texture_2d || desc.texture.samples!=1 || desc.texture.width<320 || desc.texture.height<240)return;
    if(desc.texture.width!=expectedWidth || desc.texture.height!=expectedHeight)return;
    if((desc.usage&resource_usage::shader_resource)==resource_usage::undefined || (desc.usage&resource_usage::copy_source)==resource_usage::undefined)return;
    if(owner && (owner!=dev || width!=desc.texture.width || height!=desc.texture.height))destroy(owner);
    if(!texture.handle) {
        auto backup=desc;backup.heap=memory_heap::default_;
        backup.texture.format=format::r32_float;
        backup.usage=resource_usage::shader_resource|resource_usage::copy_dest;
        backup.flags=resource_flags::none;
        if(!dev->create_resource(backup,nullptr,resource_usage::copy_dest,&texture))return;
        resource_view_desc vd(format::r32_float);
        if(!dev->create_resource_view(texture,resource_usage::shader_resource,vd,&srv)) {
            dev->destroy_resource(texture);texture={};return;
        }
        owner=dev;width=desc.texture.width;height=desc.texture.height;
    }
    copying=true;
    cmd->barrier(source,resource_usage::depth_stencil_write,resource_usage::copy_source);
    cmd->copy_resource(source,texture);
    cmd->barrier(source,resource_usage::copy_source,resource_usage::depth_stencil_write);
    copying=false;best=score;copied=GetTickCount64();
}
inline void bind(command_list* cmd,uint32_t,const resource_view*,resource_view view) {
    if(copying)return;
    if(view.handle!=current.handle){capture(cmd,current);score=0;current=view;}
}
inline bool clear(command_list* cmd,resource_view view,const float* depth,const uint8_t*,uint32_t,const rect*) {
    if(!copying && depth){capture(cmd,view);if(view.handle==current.handle)score=0;}
    return false;
}
inline void vertices(uint64_t n) {
    if(!enabled || copying || !current.handle)return;
    source_camera::Sample s{};
    if(!source_camera::read(s))return;
    const double dx=s.x-eyeX,dy=s.y-eyeY,dz=s.z-eyeZ;
    // Reject skybox cameras and the narrower first-person viewmodel projection.
    if(dx*dx+dy*dy+dz*dz<=64 && std::abs(s.fov-fov)<4 && s.nearPlane>=4)score+=n;
}
inline bool draw(command_list*,uint32_t count,uint32_t instances,uint32_t,uint32_t){vertices(uint64_t(count)*instances);return false;}
inline bool indexed(command_list*,uint32_t count,uint32_t instances,uint32_t,int32_t,uint32_t){vertices(uint64_t(count)*instances);return false;}
inline bool finish(effect_runtime* runtime,command_list* cmd) {
    runtime->get_screenshot_width_and_height(&expectedWidth,&expectedHeight);
    capture(cmd,current);
    bool fresh=enabled && srv.handle && GetTickCount64()-copied<250;
    runtime->update_texture_bindings("MC_HOST_DEPTH",fresh?srv:resource_view{},fresh?srv:resource_view{});
    score=best=0;
    return fresh;
}
inline void destroyed_view(device*,resource_view view){if(current.handle==view.handle){current={};score=0;}}
inline void register_hooks() {
    reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(bind);
    reshade::register_event<reshade::addon_event::clear_depth_stencil_view>(clear);
    reshade::register_event<reshade::addon_event::draw>(draw);
    reshade::register_event<reshade::addon_event::draw_indexed>(indexed);
    reshade::register_event<reshade::addon_event::destroy_device>(destroy);
    reshade::register_event<reshade::addon_event::destroy_resource_view>(destroyed_view);
}
}
