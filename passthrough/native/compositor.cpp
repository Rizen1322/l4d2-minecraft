#include <cstdio>
#include <algorithm>
#include "source_camera.h"
#include "source_input.h"
#include "compositor.h"
#include <windows.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>
#include <reshade.hpp>

using namespace reshade::api;

namespace
{
	constexpr const wchar_t *kMappingName = L"Local\\L4D2MinecraftFrame";
	constexpr uint32_t kMagic = 0x5450434D; // "MCPT"
	constexpr int kHeader = 4096;
	constexpr int kSlotDesc = 256;
	constexpr int kSlotDescBytes = 128;
	constexpr const char *kEffect = "L4D2Minecraft.fx";

	std::atomic<bool> g_registered{false};
	std::atomic<bool> g_active{false};
	std::atomic<float> g_hostNear{0.15f};
	std::atomic<float> g_hostFar{10000.0f};
	std::atomic<uint32_t> g_bbWidth{0}, g_bbHeight{0};
	std::atomic<bool> g_cameraLocked{false};
	std::atomic<float> g_lookLight{-1.0f}, g_lookBias{-1.0f}, g_lookSlope{-1.0f};
	std::atomic<float> g_shakeX{0.0f}, g_shakeY{0.0f}, g_shakeRoll{0.0f}, g_portalWarp{0.0f};
	float g_savedLight = -1.0f, g_savedBias = -1.0f, g_savedSlope = -1.0f;

	struct Pose
	{
		float yaw = 0, pitch = 0, roll = 0, fov = 70;
		double x = 0, y = 0, z = 0;
		bool valid = false;
	};
	std::mutex g_poseLock;
	// GTA's recent camera poses, newest last. The script reads the camera GTA is about to render (the next frame),
	// while the picture being presented was rendered with the one before: re-project to that (g_poseLag back).
	Pose g_hostPoses[4];
	unsigned g_hostPoseCount = 0;
	std::atomic<int> g_poseLag{0}; // measured: 0 matches best (third and first person)
	Pose g_mcPose;

	HANDLE g_mapping = nullptr;
	const uint8_t *g_view = nullptr;
	int32_t g_slots = 0;
	int64_t g_stride = 0;
	int64_t g_lastPublish = -1;
	DWORD g_nextOpenAttempt = 0;
	ULONGLONG g_lastNewFrame = 0;
	bool g_guestUiOpen = false;
    uint32_t g_teammates = 0;
    bool g_guestInputAlive=false;
    bool g_sceneVisible=false;
    uint32_t g_movementHeld=0;
    uint32_t g_debugMode = 0;
	int g_cursorShows = 0;
    bool g_releasedSourceMouse=false;

	struct Layer
	{
		resource tex = {0};
		resource_view srv = {0};
	};
	Layer g_world, g_depth, g_overlay;
    Layer g_worldBack, g_depthBack, g_overlayBack;
	uint32_t g_width = 0, g_height = 0;
	bool g_hasFrame = false;
	uint64_t g_hostScene = 0, g_mcScene = 0;
	float g_mcNear = 0.05f, g_mcFar = 2048.0f;
	int32_t g_mcFlags = 7;

	template <typename T>
	T read(const uint8_t *p)
	{
		T v;
		std::memcpy(&v, p, sizeof(T));
		return v;
	}

	bool open_mapping()
	{
		if (g_view != nullptr)
			return true;
		if (GetTickCount() < g_nextOpenAttempt)
			return false;
		g_nextOpenAttempt = GetTickCount() + 1000;
		g_mapping = OpenFileMappingW(FILE_MAP_READ, FALSE, kMappingName);
		if (g_mapping == nullptr)
			return false;
		const auto *header = static_cast<const uint8_t *>(MapViewOfFile(g_mapping, FILE_MAP_READ, 0, 0, kHeader));
		if (header == nullptr || read<uint32_t>(header) != kMagic)
		{
			if (header != nullptr)
				UnmapViewOfFile(header);
			CloseHandle(g_mapping);
			g_mapping = nullptr;
			return false;
		}
		g_slots = read<int32_t>(header + 12);
		g_stride = read<int64_t>(header + 16);
		if (read<int32_t>(header + 4) != 1 || read<int32_t>(header + 8) != kHeader ||
			g_slots != 3 || g_stride < 12 || g_stride > 128LL * 1024 * 1024)
		{
			UnmapViewOfFile(header);
			CloseHandle(g_mapping);
			g_mapping = nullptr;
			return false;
		}
		UnmapViewOfFile(header);
		g_view = static_cast<const uint8_t *>(MapViewOfFile(g_mapping, FILE_MAP_READ, 0, 0, static_cast<SIZE_T>(kHeader + g_stride * g_slots)));
		if (g_view == nullptr)
		{
			CloseHandle(g_mapping);
			g_mapping = nullptr;
			return false;
		}
		reshade::log::message(reshade::log::level::info, "MCPassthrough: connected to Minecraft's frame export");
		return true;
	}

	// ReShade 6.8 / API 20 is built with the MSVC x86 ABI. MinGW returns
	// 8-byte handle structs in registers instead of MSVC's hidden stack pointer.
	// The rest of the API used here has scalar returns. Call this one method
	// with an explicit result pointer and the documented thiscall convention.
	static_assert(RESHADE_API_VERSION == 20, "Revalidate ReShade ABI when updating SDK");
	effect_uniform_variable find_uniform(effect_runtime *runtime, const char *effect, const char *name)
	{
		effect_uniform_variable result = {0};
#if defined(__i386__) && defined(__MINGW32__)
		using Fn = void (__thiscall *)(effect_runtime *, effect_uniform_variable *, const char *, const char *);
		auto table = *reinterpret_cast<void ***>(runtime);
		reinterpret_cast<Fn>(table[20])(runtime, &result, effect, name);
#else
		result = runtime->find_uniform_variable(effect, name);
#endif
		return result;
	}

	void destroy_layers(device *dev)
	{
		for (Layer *layer : {&g_world, &g_depth, &g_overlay, &g_worldBack, &g_depthBack, &g_overlayBack})
		{
			if (layer->srv.handle != 0)
				dev->destroy_resource_view(layer->srv);
			if (layer->tex.handle != 0)
				dev->destroy_resource(layer->tex);
			*layer = Layer();
		}
		g_width = g_height = 0;
		g_hasFrame = false;
	}

	bool create_layer(device *dev, Layer &layer, uint32_t w, uint32_t h, format fmt)
	{
		if (!dev->create_resource(
				resource_desc(w, h, 1, 1, fmt, 1, memory_heap::default_, resource_usage::shader_resource, resource_flags::dynamic),
				nullptr, resource_usage::shader_resource, &layer.tex))
        {
            static DWORD nextLog=0;
            if(GetTickCount()>nextLog){char message[100];std::snprintf(message,sizeof(message),"MC texture creation failed: format=%u size=%ux%u",unsigned(fmt),w,h);reshade::log::message(reshade::log::level::error,message);nextLog=GetTickCount()+5000;}
            return false;
        }
        if (!dev->create_resource_view(layer.tex,resource_usage::shader_resource,resource_view_desc(fmt),&layer.srv)) {
            reshade::log::message(reshade::log::level::error,"MC texture view creation failed");return false;
        }
        return true;
	}

	void bind(effect_runtime *runtime)
	{
		runtime->update_texture_bindings("MCWORLD", g_world.srv, g_world.srv);
		runtime->update_texture_bindings("MCDEPTH", g_depth.srv, g_depth.srv);
		runtime->update_texture_bindings("MCOVERLAY", g_overlay.srv, g_overlay.srv);
	}

	/// Upload the newest published Minecraft frame, if there is one we haven't shown yet.
	void upload(effect_runtime *runtime)
	{
		const int64_t published = read<int64_t>(g_view + 32);
		if (published == g_lastPublish)
			return;
		const int32_t slot = read<int32_t>(g_view + 40);
		if (slot < 0 || slot >= g_slots)
			return;
		const uint8_t *sharedDesc = g_view + kSlotDesc + kSlotDescBytes * slot;
        uint8_t descriptor[kSlotDescBytes];
        MemoryBarrier();
        std::memcpy(descriptor, sharedDesc, sizeof(descriptor));
        const uint8_t *desc = descriptor;
		const int64_t seq = read<int64_t>(desc);
		if (seq & 1)
			return;
		const uint32_t w = read<uint32_t>(desc + 24), h = read<uint32_t>(desc + 28);
		if (w == 0 || h == 0 || w > 3840 || h > 2160 || uint64_t(w) * h * 12 > uint64_t(g_stride))
			return;
		const uint64_t scene = read<uint64_t>(desc + 104);
		const int64_t captured = read<int64_t>(desc + 88), completed = read<int64_t>(desc + 96);
		if (!scene || scene != g_hostScene || completed < captured || completed - captured > 500000000LL)
			return;
		// Bad metadata must never enter projection uniforms, even with valid pixels.
		const float nearPlane = read<float>(desc + 32), farPlane = read<float>(desc + 36), fov = read<float>(desc + 40);
		if (!std::isfinite(nearPlane) || !std::isfinite(farPlane) || !std::isfinite(fov) ||
			nearPlane <= 0 || farPlane <= nearPlane || fov <= 1 || fov >= 179) return;
		for (int offset : {48, 56, 64}) if (!std::isfinite(read<double>(desc + offset))) return;
		for (int offset : {72, 76, 80}) if (!std::isfinite(read<float>(desc + offset))) return;
		device *dev = runtime->get_device();
		if (w != g_width || h != g_height)
		{
			destroy_layers(dev);
			if (!create_layer(dev, g_world, w, h, format::r8g8b8a8_unorm) ||
				!create_layer(dev, g_depth, w, h, format::r32_float) ||
				!create_layer(dev, g_overlay, w, h, format::r8g8b8a8_unorm) ||
                !create_layer(dev,g_worldBack,w,h,format::r8g8b8a8_unorm) ||
                !create_layer(dev,g_depthBack,w,h,format::r32_float) ||
                !create_layer(dev,g_overlayBack,w,h,format::r8g8b8a8_unorm))
			{
				destroy_layers(dev);
				return;
			}
			g_width = w;
			g_height = h;
			bind(runtime);
		}
		const uint8_t *base = g_view + kHeader + g_stride * slot;
		const size_t layer = size_t(w) * h * 4;
		static std::vector<uint8_t> snapshot;
		snapshot.resize(layer * 3);
		std::memcpy(snapshot.data(), base, snapshot.size());
		MemoryBarrier();
        if (read<int64_t>(sharedDesc) != seq)
			return;
		base = snapshot.data();
        auto stream = [&](Layer& layer,const uint8_t* pixels,bool rgba) {
            subresource_data mapped{};
            if (!dev->map_texture_region(layer.tex,0,nullptr,map_access::write_discard,&mapped)) return false;
            for(uint32_t y=0;y<h;y++) {
                auto dst=static_cast<uint8_t*>(mapped.data)+size_t(y)*mapped.row_pitch;
                const auto src=pixels+size_t(y)*w*4;
                if (rgba) {
                    auto input=reinterpret_cast<const uint32_t*>(src);
                    auto output=reinterpret_cast<uint32_t*>(dst);
                    // Source's D3D9 texture is A8R8G8B8; guest bytes are RGBA.
                    for(uint32_t x=0;x<w;x++){uint32_t c=input[x];output[x]=(c&0xff00ff00)|((c&0xff)<<16)|((c>>16)&0xff);}
                } else std::memcpy(dst,src,size_t(w)*4);
            }
            dev->unmap_texture_region(layer.tex,0);
            return true;
        };
        if (!stream(g_worldBack,base,true) || !stream(g_depthBack,base+layer,false) || !stream(g_overlayBack,base+2*layer,true)) {
            static DWORD nextLog=0;
            if(GetTickCount()>nextLog){reshade::log::message(reshade::log::level::warning,"MC frame upload failed; retaining previous complete frame");nextLog=GetTickCount()+5000;}
            return;
        }
        std::swap(g_world,g_worldBack);std::swap(g_depth,g_depthBack);std::swap(g_overlay,g_overlayBack);
        bind(runtime);

        // Texture bytes and metadata came from the same accepted snapshot.
        // Never reject after upload: that would leave new pixels with an old pose.
		g_lastPublish = published;
		g_lastNewFrame = GetTickCount64();
		g_mcNear = read<float>(desc + 32);
		g_mcFar = read<float>(desc + 36);
		g_mcFlags = read<int32_t>(desc + 44);
		g_mcPose.fov = read<float>(desc + 40);
		g_mcPose.yaw = read<float>(desc + 72);
		g_mcPose.pitch = read<float>(desc + 76);
		g_mcPose.roll = read<float>(desc + 80);
		g_mcPose.x = read<double>(desc + 48);
		g_mcPose.y = read<double>(desc + 56);
		g_mcPose.z = read<double>(desc + 64);
		g_mcPose.valid = true;
		g_hasFrame = true;
		g_mcScene = scene;
	}

	/// Camera-to-world rotation, as Minecraft builds it: rotationYXZ(pi - yaw, -pitch, roll) (camera looks down -z).
	void camera_rotation(const Pose &p, float m[3][3])
	{
		const float d2r = 3.14159265f / 180.0f;
		const float a = 3.14159265f - p.yaw * d2r, b = -p.pitch * d2r, c = p.roll * d2r;
		const float ca = std::cos(a), sa = std::sin(a), cb = std::cos(b), sb = std::sin(b), cc = std::cos(c), sc = std::sin(c);
		// Ry(a) * Rx(b) * Rz(c)
		const float ry[3][3] = {{ca, 0, sa}, {0, 1, 0}, {-sa, 0, ca}};
		const float rx[3][3] = {{1, 0, 0}, {0, cb, -sb}, {0, sb, cb}};
		const float rz[3][3] = {{cc, -sc, 0}, {sc, cc, 0}, {0, 0, 1}};
		float t[3][3] = {};
		for (int i = 0; i < 3; ++i)
			for (int j = 0; j < 3; ++j)
				for (int k = 0; k < 3; ++k)
					t[i][j] += ry[i][k] * rx[k][j];
		for (int i = 0; i < 3; ++i)
			for (int j = 0; j < 3; ++j)
			{
				m[i][j] = 0;
				for (int k = 0; k < 3; ++k)
					m[i][j] += t[i][k] * rz[k][j];
			}
	}

	/// Rows of R_mc^T * R_host: turns a ray in GTA's camera space into Minecraft's camera space.
	void warp_matrix(const Pose &host, const Pose &mc, float out[3][3])
	{
		float rh[3][3], rm[3][3];
		camera_rotation(host, rh);
		camera_rotation(mc, rm);
		for (int i = 0; i < 3; ++i)
			for (int j = 0; j < 3; ++j)
			{
				out[i][j] = 0;
				for (int k = 0; k < 3; ++k)
					out[i][j] += rm[k][i] * rh[k][j];
			}
	}

	/// Reload L4D2Minecraft.fx when the file changes (ReShade doesn't watch it), so tweaks don't need a GTA restart.
	void watch_effect_file(effect_runtime *runtime)
	{
		static DWORD next = 0;
		static FILETIME last = {};
		static wchar_t path[MAX_PATH] = {};
		if (GetTickCount() < next)
			return;
		next = GetTickCount() + 1000;
		if (path[0] == 0)
		{
			HMODULE addon=nullptr;
            GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&watch_effect_file),&addon);
            GetModuleFileNameW(addon, path, MAX_PATH);
			wchar_t *slash = wcsrchr(path, L'\\');
			if (slash)
				wcscpy_s(slash + 1, MAX_PATH - (slash + 1 - path), L"shaders\\L4D2Minecraft.fx");
		}
		WIN32_FILE_ATTRIBUTE_DATA info;
		if (!GetFileAttributesExW(path, GetFileExInfoStandard, &info))
			return;
		if (last.dwLowDateTime != 0 && CompareFileTime(&info.ftLastWriteTime, &last) != 0)
			runtime->reload_effect_next_frame(kEffect);
		last = info.ftLastWriteTime;
	}

    int g_worldCursorHides=0;
    void restore_world_cursor_counter() {
        while(g_worldCursorHides>0){ShowCursor(TRUE);--g_worldCursorHides;}
    }
	void on_present(effect_runtime *runtime)
	{
        source_camera::publish_visibility(source_camera::gameplay_visible());
        const bool hostMenu=source_camera::menu_visible();
        const bool worldCursor=!hostMenu && g_active && g_sceneVisible && g_guestInputAlive && !g_guestUiOpen
            && source_camera::gameplay_visible() && GetForegroundWindow()==runtime->get_hwnd();
        if(!worldCursor)restore_world_cursor_counter();
		watch_effect_file(runtime);
        if(hostMenu) {
            while(g_cursorShows>0){ShowCursor(FALSE);--g_cursorShows;}
            source_input::yield_to_menu();
            g_releasedSourceMouse=false;
            return;
        }
		if (g_guestUiOpen && g_guestInputAlive && g_sceneVisible && source_camera::gameplay_visible() &&
			GetForegroundWindow() == runtime->get_hwnd())
		{
			source_input::mouse(false);
            g_releasedSourceMouse=true;
			// Source must receive Escape even while the Minecraft inventory is open.
			ClipCursor(nullptr);
			if (g_cursorShows == 0) {
				int count;
				do { count = ShowCursor(TRUE); ++g_cursorShows; } while (count < 0 && g_cursorShows < 32);
			}
			SetCursor(LoadCursorW(nullptr, MAKEINTRESOURCEW(32512)));
		}
		else {
            if(g_releasedSourceMouse) {
                // Let Source own look input again when closing the guest screen.
                const bool focus=GetForegroundWindow()==runtime->get_hwnd();
                source_input::mouse(true,focus);
                g_releasedSourceMouse=false;
            }
            while (g_cursorShows > 0) { ShowCursor(FALSE); --g_cursorShows; }
            if(g_active && g_sceneVisible && g_guestInputAlive && !g_guestUiOpen && source_camera::gameplay_visible() && GetForegroundWindow()==runtime->get_hwnd()) {
                source_input::mouse(true,true);
                SetCursor(nullptr);
                CURSORINFO cursor{};cursor.cbSize=sizeof(cursor);
                if(GetCursorInfo(&cursor) && (cursor.flags&CURSOR_SHOWING)) {
                    int count;
                    do{count=ShowCursor(FALSE);++g_worldCursorHides;}while(count>=0 && g_worldCursorHides<32);
                }
            }
        }
	}

	void read_host_pose();
	void on_begin_effects(effect_runtime *runtime, command_list *commands, resource_view, resource_view)
	{
		read_host_pose();
		uint32_t bw = 0, bh = 0;
		runtime->get_screenshot_width_and_height(&bw, &bh);
		g_bbWidth = bw;
		g_bbHeight = bh;
		bool on = g_active && g_sceneVisible && !source_camera::menu_visible() && source_camera::gameplay_visible() && open_mapping();
		if (on)
			upload(runtime);
		on = on && g_hasFrame && g_hostScene != 0 && g_mcScene == g_hostScene && GetTickCount64() - g_lastNewFrame < 500;
		// The technique stays enabled (preset); McActive gates it, so GTA passes through untouched until a
		// Minecraft frame is here. (Toggling techniques from inside this callback crashes ReShade.)
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "McActive"); v.handle != 0)
			runtime->set_uniform_value_bool(v, on);
        if (const auto v=find_uniform(runtime,kEffect,"TeammateHudCount");v.handle)
            runtime->set_uniform_value_int(v,on && !g_guestUiOpen?int(g_teammates):0);
        if (const auto v=find_uniform(runtime,kEffect,"DebugView");v.handle) runtime->set_uniform_value_int(v,g_debugMode<=3?int(g_debugMode):0);
        if (const auto v=find_uniform(runtime,kEffect,"HostOcclusion");v.handle) runtime->set_uniform_value_bool(v,g_debugMode!=4);
        if (const auto v=find_uniform(runtime,kEffect,"Reproject");v.handle) runtime->set_uniform_value_bool(v,g_debugMode!=5);

		if (!on)
			return;
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "McPlanes"); v.handle != 0)
			runtime->set_uniform_value_float(v, g_mcNear, g_mcFar, float(g_mcFlags));
		// a scene's look overrides the preset's light matching and depth bias; the preset's values come back after
		auto look = [&](const char *name, float want, float &saved) {
			const effect_uniform_variable v = find_uniform(runtime, kEffect, name);
			if (v.handle == 0)
				return;
			if (want >= 0.0f)
			{
				if (saved < 0.0f)
					runtime->get_uniform_value_float(v, &saved, 1);
				runtime->set_uniform_value_float(v, want);
			}
			else if (saved >= 0.0f)
			{
				runtime->set_uniform_value_float(v, saved);
				saved = -1.0f;
			}
		};
		look("LightMatch", g_lookLight.load(), g_savedLight);
		look("DepthBias", g_lookBias.load(), g_savedBias);
		look("SlopeBias", g_lookSlope.load(), g_savedSlope);
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "Shake"); v.handle != 0)
			runtime->set_uniform_value_float(v, g_shakeX.load(), g_shakeY.load(), g_shakeRoll.load());
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "PortalWarp"); v.handle != 0)
			runtime->set_uniform_value_float(v, g_portalWarp.load());
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "HostPlanes"); v.handle != 0)
			runtime->set_uniform_value_float(v, g_hostNear.load(), g_hostFar.load());

		// Re-projection from Minecraft's pose to GTA's latest (extrapolated by the effect's PosePrediction frames).
		Pose host, prev;
		{
			std::lock_guard<std::mutex> lock(g_poseLock);
			const unsigned lag = unsigned(std::clamp(g_poseLag.load(), 0, 2));
			if (g_hostPoseCount > lag)
				host = g_hostPoses[(g_hostPoseCount - 1 - lag) & 3];
			if (g_hostPoseCount > lag + 1)
				prev = g_hostPoses[(g_hostPoseCount - 2 - lag) & 3];
		}
		float predict = 0.0f;
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "PosePrediction"); v.handle != 0)
			runtime->get_uniform_value_float(v, &predict, 1);
		const bool warp = host.valid && g_mcPose.valid && !g_cameraLocked;
		if (warp && prev.valid && predict != 0.0f)
		{
			auto delta = [](float a, float b) { float d = std::fmod(a - b + 540.0f, 360.0f) - 180.0f; return d; };
			host.yaw += delta(host.yaw, prev.yaw) * predict;
			host.pitch += (host.pitch - prev.pitch) * predict;
			host.roll += (host.roll - prev.roll) * predict;
			host.x += (host.x - prev.x) * predict;
			host.y += (host.y - prev.y) * predict;
			host.z += (host.z - prev.z) * predict;
		}
		float m[3][3] = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}};
		float t[3] = {0, 0, 0};
		if (warp)
		{
			warp_matrix(host, g_mcPose, m);
			// T = R_mc^T (host position - Minecraft's camera position), in Minecraft's camera space
			float rm[3][3];
			camera_rotation(g_mcPose, rm);
			const float d[3] = {float(host.x - g_mcPose.x), float(host.y - g_mcPose.y), float(host.z - g_mcPose.z)};
			for (int i = 0; i < 3; ++i)
				t[i] = rm[0][i] * d[0] + rm[1][i] * d[1] + rm[2][i] * d[2];
		}
		const char *rows[3] = {"WarpRow0", "WarpRow1", "WarpRow2"};
		for (int i = 0; i < 3; ++i)
			if (const effect_uniform_variable v = find_uniform(runtime, kEffect, rows[i]); v.handle != 0)
				runtime->set_uniform_value_float(v, m[i][0], m[i][1], m[i][2]);
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "WarpT"); v.handle != 0)
			runtime->set_uniform_value_float(v, t[0], t[1], t[2]);
		const float d2r = 3.14159265f / 180.0f;
		const float tanHost = std::tan((warp ? host.fov : g_mcPose.fov) * d2r * 0.5f), tanMc = std::tan(g_mcPose.fov * d2r * 0.5f);
		if (const effect_uniform_variable v = find_uniform(runtime, kEffect, "WarpTan"); v.handle != 0)
			runtime->set_uniform_value_float(v, tanHost, tanMc, float(g_width) / float(g_height));
	}

	void read_host_pose()
	{
        static uint64_t lastAccepted=0,lastInputAccepted=0;
        const auto inputNow=GetTickCount64();
        g_guestInputAlive=lastInputAccepted>0 && inputNow>=lastInputAccepted && inputNow-lastInputAccepted<1000;
        if(GetTickCount64()-lastAccepted>=500) {compositor::set_active(false);}
		static HANDLE mapping = nullptr;
		static const uint8_t *view = nullptr;
		if (!view) {
			mapping = OpenFileMappingW(FILE_MAP_READ, FALSE, L"Local\\L4D2MinecraftPose");
			if (mapping) view = static_cast<const uint8_t *>(MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 128));
		}
		if (!view) { compositor::set_active(false); return; }
		const uint32_t seq = read<uint32_t>(view + 4);
		if ((seq & 1) || read<uint32_t>(view) != 0x50434D4C) return; // Hold the last complete pose across an in-progress write.
		const uint64_t timestamp = read<uint64_t>(view + 8);
		const auto inputStamp=read<uint64_t>(view+72),now=GetTickCount64();
		const bool uiOpen = read<uint32_t>(view + 64) != 0;
		const uint32_t held = read<uint32_t>(view + 80) & 127, debug = read<uint32_t>(view + 68);
		const bool sceneVisible = read<uint32_t>(view + 84) != 0;
		const uint64_t scene = read<uint64_t>(view + 88);
        const uint32_t teammates = read<uint32_t>(view + 96);
		const double x = read<double>(view+16), y = read<double>(view+24), z = read<double>(view+32);
		const float yaw = read<float>(view+40), pitch = read<float>(view+44), roll = read<float>(view+48), fov = read<float>(view+52);
		MemoryBarrier();
		if (read<uint32_t>(view+4) != seq) return;
		lastInputAccepted=inputStamp;
		g_guestInputAlive=inputStamp>0 && now>=inputStamp && now-inputStamp<1000;
		g_guestUiOpen=uiOpen;g_movementHeld=held;g_sceneVisible=sceneVisible;g_debugMode=debug;
        g_teammates=teammates<=3?teammates:0;
		if (scene != g_hostScene) { g_hasFrame=false;g_hostScene=scene; }
		const bool fresh = GetTickCount64() >= timestamp && GetTickCount64() - timestamp < 500;
		compositor::set_active(fresh);
        if(fresh) lastAccepted=timestamp;
		if (fresh) {
            source_camera::Sample actual{};
            static source_camera::Sample lastCamera{};
            static bool haveCamera=false;
            const bool readCamera=source_camera::read(actual);
            const double dx=actual.x-x,dy=actual.y-y,dz=actual.z-z;
            // Engine matrices can briefly describe a distant auxiliary view.
            // Cross-check against the independently validated player eye before
            // publishing it to Minecraft or using it for reprojection.
            if (readCamera && dx*dx+dy*dy+dz*dz<=64.0) {
                lastCamera=actual;haveCamera=true;
            } else if(haveCamera) {
                actual=lastCamera;
                actual.x=x;actual.y=y;actual.z=z;
                actual.yaw=yaw;actual.pitch=pitch;actual.roll=roll;
            }
            if (haveCamera) {
                source_camera::publish(actual);
                compositor::set_host_planes(actual.nearPlane,actual.farPlane);
                compositor::set_host_pose(actual.yaw,actual.pitch,actual.roll,actual.fov,actual.x,actual.y,actual.z);
            } else compositor::set_host_pose(yaw,pitch,roll,fov,x,y,z);
        }
	}

	void on_reloaded_effects(effect_runtime *runtime)
	{
		if (g_width != 0)
			bind(runtime);
	}

	void on_destroy_effect_runtime(effect_runtime *runtime)
	{
		destroy_layers(runtime->get_device());
	}
}

namespace compositor
{
	bool try_register(void *module)
	{
		if (g_registered)
			return true;
		if (!reshade::register_addon(module))
			return false;
		reshade::register_event<reshade::addon_event::reshade_begin_effects>(on_begin_effects);
		reshade::register_event<reshade::addon_event::reshade_present>(on_present);
		reshade::register_event<reshade::addon_event::reshade_reloaded_effects>(on_reloaded_effects);
		reshade::register_event<reshade::addon_event::destroy_effect_runtime>(on_destroy_effect_runtime);
        // Experimental capture is disabled until its depth output is validated.
		g_registered = true;
		reshade::log::message(reshade::log::level::info, "MCPassthrough: registered");
		return true;
	}

	void unregister(void *module)
	{
		restore_world_cursor_counter();
        while(g_cursorShows>0){ShowCursor(FALSE);--g_cursorShows;}
		source_input::restore();
		if (g_registered.exchange(false))
			reshade::unregister_addon(module);
	}

	void set_active(bool active)
	{
		g_active = active;
	}

	void set_host_planes(float near_clip, float far_clip)
	{
		g_hostNear = near_clip;
		g_hostFar = far_clip;
	}

	void backbuffer_size(int &width, int &height)
	{
		width = int(g_bbWidth.load());
		height = int(g_bbHeight.load());
	}

	void set_camera_locked(bool locked)
	{
		g_cameraLocked = locked;
	}

	void set_screen_fx(float shake_x, float shake_y, float shake_roll, float portal_warp)
	{
		g_shakeX = shake_x;
		g_shakeY = shake_y;
		g_shakeRoll = shake_roll;
		g_portalWarp = portal_warp;
	}

	void set_look(float light_match, float depth_bias, float slope_bias)
	{
		g_lookLight = light_match;
		g_lookBias = depth_bias;
		g_lookSlope = slope_bias;
	}

	void set_host_pose(float yaw, float pitch, float roll, float fov, double x, double y, double z)
	{
		std::lock_guard<std::mutex> lock(g_poseLock);
		g_hostPoses[g_hostPoseCount & 3] = {yaw, pitch, roll, fov, x, y, z, true};
		++g_hostPoseCount;
	}

	void set_pose_lag(int frames)
	{
		g_poseLag = frames;
	}
}
