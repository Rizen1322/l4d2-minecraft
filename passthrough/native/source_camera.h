#pragma once
#include <windows.h>
#include <cmath>
#include <cstdint>
#include <cstring>

// L4D2 VEngineClient013 differs from SDK2013: HideLoadingPlaque occupies slot29.
// Read-only view API: no hooks, engine writes or offsets into player structures.
// Slot references: Lak3/l4d2-internal-base SDK/L4D2/Interfaces/EngineClient.h.
namespace source_camera {
struct Sample { double x,y,z; float yaw,pitch,roll,fov,nearPlane,farPlane; };
inline bool readable(const void* p, size_t bytes) {
    MEMORY_BASIC_INFORMATION m{};
    if (!p || !VirtualQuery(p,&m,sizeof(m)) || m.State!=MEM_COMMIT || (m.Protect&(PAGE_NOACCESS|PAGE_GUARD))) return false;
    return reinterpret_cast<uintptr_t>(p)+bytes<=reinterpret_cast<uintptr_t>(m.BaseAddress)+m.RegionSize;
}
// Read-only methods before the validated matrix slots in this exact interface.
inline bool gameplay_visible() {
    static void* engine=nullptr;
    if(!engine) {
        auto module=GetModuleHandleW(L"engine.dll");
        auto factory=module?reinterpret_cast<void*(__cdecl*)(const char*,int*)>(GetProcAddress(module,"CreateInterface")):nullptr;
        engine=factory?factory("VEngineClient013",nullptr):nullptr;
    }
    if(!readable(engine,sizeof(void*)))return false;
    auto table=*reinterpret_cast<void***>(engine);
    if(!readable(table,29*sizeof(void*)))return false;
    using Flag=bool(__thiscall*)(void*);
    return reinterpret_cast<Flag>(table[26])(engine) && !reinterpret_cast<Flag>(table[28])(engine);
}
// VEngineVGui001: destructor, GetPanel, IsGameUIVisible (slot 2).
// Valve public ienginevgui.h and the L4D2 SDK EngineVGui.h agree on these slots.
inline bool menu_visible() {
    static void* vgui=nullptr;
    if(!vgui) {
        auto module=GetModuleHandleW(L"engine.dll");
        auto factory=module?reinterpret_cast<void*(__cdecl*)(const char*,int*)>(GetProcAddress(module,"CreateInterface")):nullptr;
        vgui=factory?factory("VEngineVGui001",nullptr):nullptr;
    }
    if(!readable(vgui,sizeof(void*)))return false;
    auto table=*reinterpret_cast<void***>(vgui);
    if(!readable(table,3*sizeof(void*)))return false;
    return reinterpret_cast<bool(__thiscall*)(void*)>(table[2])(vgui);
}
inline bool read(Sample& s) {
    static void* engine=nullptr;
    if (!engine) {
        HMODULE module=GetModuleHandleW(L"engine.dll");
        if (!module) return false;
        auto factory=reinterpret_cast<void*(__cdecl*)(const char*,int*)>(GetProcAddress(module,"CreateInterface"));
        if (!factory) return false;
        engine=factory("VEngineClient013",nullptr);
    }
    if (!readable(engine,sizeof(void*))) return false;
    auto table=*reinterpret_cast<void***>(engine);
    if (!readable(table,39*sizeof(void*))) return false;
    using MatrixFn=const float*(__thiscall*)(void*);
    const float* projection=reinterpret_cast<MatrixFn>(table[37])(engine);
    const float* view=reinterpret_cast<MatrixFn>(table[38])(engine);
    if (!readable(projection,64)||!readable(view,64)) return false;
    float p[16],v[16]; std::memcpy(p,projection,64);std::memcpy(v,view,64);
    for (int i=0;i<16;i++) if (!std::isfinite(p[i])||!std::isfinite(v[i])) return false;
    for (int i=0;i<3;i++) {
        float norm=0;for(int j=0;j<3;j++) norm+=v[i*4+j]*v[i*4+j];
        if (std::abs(norm-1)>0.01f) return false;
    }
    float position[3]={};
    for(int j=0;j<3;j++) for(int i=0;i<3;i++) position[j]-=v[i*4+j]*v[i*4+3];
    // Camera forward is minus the last view row; convert Source (x,y,z) to MC (x,z,-y).
    const float fx=-v[8], fy=-v[10], fz=v[9], degrees=57.295779513f;
    s.x=position[0]/32.0;s.y=position[2]/32.0;s.z=-position[1]/32.0;
    s.yaw=std::atan2(-fx,fz)*degrees;s.pitch=std::asin(std::clamp(-fy,-1.0f,1.0f))*degrees;
    s.roll=0; // Ordinary local first-person camera; recover roll from view right/up below.
    float right[3]={v[0],v[2],-v[1]};
    float yaw=s.yaw/degrees;
    float baseRight[3]={-std::cos(yaw),0,-std::sin(yaw)};
    float baseUp[3]={-std::sin(yaw)*std::sin(s.pitch/degrees),std::cos(s.pitch/degrees),std::cos(yaw)*std::sin(s.pitch/degrees)};
    float c=0,b=0;for(int j=0;j<3;j++){c+=right[j]*baseRight[j];b+=right[j]*baseUp[j];}
    s.roll=std::atan2(b,c)*degrees;
    float cot=std::sqrt(p[4]*p[4]+p[5]*p[5]+p[6]*p[6]);
    if(cot<0.1f||cot>20) return false;
    s.fov=2*std::atan(1/cot)*degrees;
    float a=-(p[8]*v[8]+p[9]*v[9]+p[10]*v[10]);
    float bdepth=p[11]+a*v[11];
    s.nearPlane=-bdepth/a;s.farPlane=-bdepth/(a-1);
    if (!std::isfinite(s.fov)||!std::isfinite(s.nearPlane)||!std::isfinite(s.farPlane) ||
        !(s.nearPlane>0&&s.nearPlane<100&&s.farPlane>s.nearPlane)) return false;
    return true;
}
inline void publish_visibility(bool ready) {
    static HANDLE map=CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,128,L"Local\\L4D2MinecraftRenderPose");
    static uint8_t* data=map?static_cast<uint8_t*>(MapViewOfFile(map,FILE_MAP_WRITE,0,0,128)):nullptr;
    if(!data)return;
    uint32_t flag=ready?1:0;uint64_t stamp=GetTickCount64();
    uint32_t menu=menu_visible()?1:0;
    std::memcpy(data+80,&menu,sizeof(menu));std::memcpy(data+64,&flag,sizeof(flag));MemoryBarrier();std::memcpy(data+72,&stamp,sizeof(stamp));
}
inline void publish(const Sample& s) {
    static HANDLE map=CreateFileMappingW(INVALID_HANDLE_VALUE,nullptr,PAGE_READWRITE,0,128,L"Local\\L4D2MinecraftRenderPose");
    static uint8_t* data=map?static_cast<uint8_t*>(MapViewOfFile(map,FILE_MAP_WRITE,0,0,128)):nullptr;
    static uint32_t sequence=0;
    if(!data) return;
    sequence+=2;
    auto write=[&](size_t offset,auto value){std::memcpy(data+offset,&value,sizeof(value));};
    write(4,sequence-1);MemoryBarrier();write(0,uint32_t(0x50434D4C));write(8,GetTickCount64());
    write(16,s.x);write(24,s.y);write(32,s.z);write(40,s.yaw);write(44,s.pitch);write(48,s.roll);write(52,s.fov);
    write(56,s.nearPlane);write(60,s.farPlane);MemoryBarrier();write(4,sequence);
}
}
