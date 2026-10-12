#pragma once
#include <d3d9.h>
#include <reshade.hpp>
// Compose into the native scene before Source copies it for screen-space
// effects. Keep the normal presentation path when no compatible copy occurs.
namespace source_postprocess {
inline reshade::api::effect_runtime* runtime=nullptr;
inline reshade::api::resource_view target{};
inline uint64_t surface=0;
inline bool rendering=false,done=false;
inline uint64_t count=0;
inline uint32_t copies=0;
inline void screenshot(reshade::api::effect_runtime* value,const wchar_t* file=L"capture.rgba",bool force=false){
    wchar_t folder[MAX_PATH]{};if(!GetEnvironmentVariableW(L"L4D2MC_CAPTURE_DIR",folder,MAX_PATH))return;
    std::wstring request=std::wstring(folder)+L"\\capture.request";
    if(!force && GetFileAttributesW(request.c_str())==INVALID_FILE_ATTRIBUTES)return;
    if(!force && !DeleteFileW(request.c_str()))return;
    uint32_t w=0,h=0;value->get_screenshot_width_and_height(&w,&h);
    if(!w || !h || w>3840 || h>2160)return;
    std::vector<uint8_t> pixels(size_t(w)*h*4);
    if(!value->capture_screenshot(pixels.data()))return;
    FILE* output=nullptr;std::wstring name=std::wstring(folder)+L"\\"+file;
    if(_wfopen_s(&output,name.c_str(),L"wb") || !output)return;
    fwrite(&w,4,1,output);fwrite(&h,4,1,output);fwrite(pixels.data(),1,pixels.size(),output);fclose(output);
}
inline bool enabled(){wchar_t value[8]{};return !GetEnvironmentVariableW(L"L4D2MC_EARLY_EFFECTS",value,8) || value[0]!=L'0';}
inline void initialize(reshade::api::effect_runtime* value){runtime=value;done=false;}
inline void present(reshade::api::effect_runtime* value){runtime=value;done=false;copies=0;screenshot(value);}
inline void destroy(reshade::api::effect_runtime* value){if(value!=runtime)return;if(target.handle)value->get_device()->destroy_resource_view(target);target={};surface=0;runtime=nullptr;done=false;}
inline bool copy(reshade::api::command_list* commands,reshade::api::resource source,uint32_t sourceSubresource,const reshade::api::subresource_box* sourceBox,reshade::api::resource destination,uint32_t destinationSubresource,const reshade::api::subresource_box* destinationBox,reshade::api::filter_mode){
    if(!enabled() || !runtime || rendering || done || sourceSubresource || destinationSubresource || source.handle==destination.handle || commands->get_device()!=runtime->get_device())return false;
    auto device=reinterpret_cast<IDirect3DDevice9*>(static_cast<uintptr_t>(commands->get_native()));
    IDirect3DSurface9* back=nullptr;
    if(FAILED(device->GetBackBuffer(0,0,D3DBACKBUFFER_TYPE_MONO,&back)))return false;
    bool matches=reinterpret_cast<uintptr_t>(back)==source.handle;
    D3DSURFACE_DESC desc{};back->GetDesc(&desc);back->Release();
    if(!matches || desc.Width<320 || desc.Height<240 || desc.MultiSampleType!=D3DMULTISAMPLE_NONE)return false;
    // Bloom/refraction also copy the backbuffer into smaller targets. They are
    // not a full-scene checkpoint, even when Source omits the region boxes.
    // D3D9 COM calls use explicit output parameters. Avoid ReShade's by-value
    // resource_desc across its MSVC / our MinGW x86 ABI boundary.
    if(!destination.handle)return false;
    auto nativeOutput=reinterpret_cast<IDirect3DResource9*>(static_cast<uintptr_t>(destination.handle));
    D3DSURFACE_DESC output{};HRESULT described=E_FAIL;
    switch(nativeOutput->GetType()) {
        case D3DRTYPE_SURFACE:described=reinterpret_cast<IDirect3DSurface9*>(nativeOutput)->GetDesc(&output);break;
        case D3DRTYPE_TEXTURE:described=reinterpret_cast<IDirect3DTexture9*>(nativeOutput)->GetLevelDesc(0,&output);break;
        default:return false;
    }
    if(FAILED(described) || output.Width!=desc.Width || output.Height!=desc.Height)return false;
    if(sourceBox && (sourceBox->left || sourceBox->top || sourceBox->right!=desc.Width || sourceBox->bottom!=desc.Height))return false;
    if(destinationBox && (destinationBox->left || destinationBox->top || destinationBox->right!=desc.Width || destinationBox->bottom!=desc.Height))return false;
    // First copy precedes translucent Source geometry. The second is the
    // full-frame post-process input; composing earlier lets fences/props draw
    // over opaque guest blocks. A missing second copy retains present fallback.
    if(++copies<2)return false;
    if(source.handle!=surface){
        if(target.handle)runtime->get_device()->destroy_resource_view(target);
        target={};surface=source.handle;
        if(!runtime->get_device()->create_resource_view(source,reshade::api::resource_usage::render_target,reshade::api::resource_view_desc(reshade::api::format::b8g8r8a8_unorm),&target))return false;
    }
    IDirect3DStateBlock9* saved=nullptr;IDirect3DSurface9* color[4]{},*depth=nullptr;
    if(FAILED(device->CreateStateBlock(D3DSBT_ALL,&saved)))return false;
    saved->Capture();for(unsigned i=0;i<4;i++)device->GetRenderTarget(i,&color[i]);device->GetDepthStencilSurface(&depth);
    const bool began=SUCCEEDED(device->BeginScene());
    rendering=true;done=true;
    runtime->render_effects(commands,target,target);
    for(unsigned i=0;i<4;i++){device->SetRenderTarget(i,color[i]);if(color[i])color[i]->Release();}
    device->SetDepthStencilSurface(depth);if(depth)depth->Release();saved->Apply();saved->Release();if(began)device->EndScene();rendering=false;
    if(++count==1)reshade::log::message(reshade::log::level::info,"L4D2MC: composed before native screen-space copy");
    return false;
}
}
