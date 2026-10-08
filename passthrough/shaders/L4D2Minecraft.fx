// Composites Minecraft (passthrough mod) into L4D2 V. The MCPassthrough add-on (MCPassthrough.asi) uploads
// Minecraft's latest frame into the MCWORLD / MCDEPTH / MCOVERLAY textures and sets the plane uniforms.
//
// world: premultiplied RGBA, drawn where Minecraft is nearer than L4D2's depth buffer (both in metres).
// overlay: Minecraft's hand, HUD and screens, always on top.
#include "ReShade.fxh"

texture MCWorldTex : MCWORLD;
texture MCDepthTex : MCDEPTH;
texture MCOverlayTex : MCOVERLAY;
sampler sWorld { Texture = MCWorldTex; AddressU = CLAMP; AddressV = CLAMP; };
sampler sDepth { Texture = MCDepthTex; MinFilter = POINT; MagFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
sampler sOverlay { Texture = MCOverlayTex; AddressU = CLAMP; AddressV = CLAMP; };

// x = near, y = far, z = flags (1: [0,1] depth, 2: rows bottom-up, 4: reversed Z). Set by the add-on.
uniform float3 McPlanes = float3(0.05, 2048.0, 7.0);
// L4D2's camera near/far clip. Set by the add-on.
uniform float2 HostPlanes = float2(7.0, 30000.0);

// Set true by the add-on only while it has uploaded a Minecraft frame; until then L4D2 passes through untouched.
uniform bool McActive = false;

uniform bool HostOcclusion = true;
uniform bool HostReversedZ < ui_label = "L4D2 depth is reversed"; > = false;
uniform float DepthBias < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.005; ui_label = "Depth bias (m)";
	ui_tooltip = "How far behind L4D2's surface Minecraft may still show (blocks resting on the ground)."; > = 0.04;
uniform float SlopeBias < ui_type = "drag"; ui_min = 0.0; ui_max = 40.0; ui_step = 0.1; ui_label = "Depth bias per grazing slope";
	ui_tooltip = "Extra depth bias where L4D2's surface is seen at a grazing angle (its depth changes fast down the screen): Minecraft ground laid into L4D2's (lava, netherrack) still shows far away."; > = 0.0;
uniform float MaxBias < ui_type = "drag"; ui_min = 0.1; ui_max = 10.0; ui_step = 0.1; ui_label = "Largest depth bias (m)"; > = 3.0;
uniform float HostDepthScale < ui_type = "drag"; ui_min = 0.001; ui_max = 2.0; ui_step = 0.001; ui_label = "L4D2 depth scale";
	ui_tooltip = "Calibration: multiplies L4D2's linearised depth."; > = 0.03125;
uniform float LightMatch < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Match L4D2 lighting";
	ui_tooltip = "Relight Minecraft by the (blurred) L4D2 picture around it: darker in shade, tinted by nearby light."; > = 0.8;
uniform float LightReference < ui_type = "drag"; ui_min = 0.1; ui_max = 1.0; ui_step = 0.01; ui_label = "Neutral brightness";
	ui_tooltip = "L4D2 brightness at which Minecraft keeps its own colours."; > = 0.42;
uniform float LightTint < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Light colour"; > = 0.55;
uniform float LightBlur < ui_type = "drag"; ui_min = 1.0; ui_max = 6.0; ui_step = 0.1; ui_label = "Light blur (mip)"; > = 3.2;
uniform float GradeMatch < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Match L4D2 colour grade";
	ui_tooltip = "Give Minecraft the colour of L4D2's whole picture (a red Nether night, an orange sunset), as L4D2's own grading does to its world."; > = 0.55;
uniform float HazeStart < ui_type = "drag"; ui_min = 0.0; ui_max = 200.0; ui_step = 1.0; ui_label = "Haze start (m)"; > = 15.0;
uniform float HazeDistance < ui_type = "drag"; ui_min = 10.0; ui_max = 1000.0; ui_step = 1.0; ui_label = "Haze distance (m)";
	ui_tooltip = "Far away, Minecraft fades into the L4D2 picture around it (L4D2's haze and fog don't reach Minecraft otherwise)."; > = 160.0;
uniform float HazeStrength < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Haze strength"; > = 0.85;
uniform float EdgeSoftness < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Soften Minecraft's edges";
	ui_tooltip = "Anti-alias where Minecraft meets L4D2 (L4D2's own anti-aliasing ran before Minecraft was added)."; > = 1.0;
uniform float ContactShadow < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Contact shadows";
	ui_tooltip = "Darken L4D2's surfaces right next to Minecraft's (under mobs' feet, around blocks)."; > = 0.5;
uniform float ContactRadius < ui_type = "drag"; ui_min = 0.1; ui_max = 3.0; ui_step = 0.05; ui_label = "Contact shadow size (m)"; > = 0.7;
uniform float BloomStrength < ui_type = "drag"; ui_min = 0.0; ui_max = 2.0; ui_step = 0.01; ui_label = "Minecraft glow";
	ui_tooltip = "Bright Minecraft things (lava, fire, the portal) glow over L4D2's picture, as L4D2's own lights do."; > = 0.55;
uniform float BloomThreshold < ui_type = "drag"; ui_min = 0.0; ui_max = 1.0; ui_step = 0.01; ui_label = "Glow threshold"; > = 0.62;
// Set by the add-on: the camera shake, applied to the finished picture so L4D2 and Minecraft shake together
// (x, y: fraction of the screen height; z: roll, radians), and the nether portal's warp (0..1) while passing through.
uniform float3 Shake = float3(0.0, 0.0, 0.0);
uniform float PortalWarp = 0.0;
uniform float Timer < source = "timer"; >;
uniform int DebugView < ui_type = "combo"; ui_items = "Composite\0L4D2 depth (1 m bands)\0Minecraft depth (1 m bands)\0Depth difference\0"; > = 0;
uniform bool Reproject < ui_label = "Re-project to L4D2's camera"; ui_tooltip = "Rotate Minecraft's (slightly older) frame onto L4D2's current camera."; > = true;
uniform float PosePrediction < ui_type = "drag"; ui_min = -2.0; ui_max = 3.0; ui_step = 0.05; ui_label = "Pose prediction (frames)";
	ui_tooltip = "Extrapolate L4D2's camera rotation by this many frames before re-projecting."; > = 0.0;

// Set by the add-on: rows of R_mc^T R_source (L4D2 camera ray -> Minecraft camera ray), and
// x = tan(L4D2 vertical fov / 2), y = tan(Minecraft vertical fov / 2), z = Minecraft aspect.
uniform float3 WarpRow0 = float3(1.0, 0.0, 0.0);
uniform float3 WarpRow1 = float3(0.0, 1.0, 0.0);
uniform float3 WarpRow2 = float3(0.0, 0.0, 1.0);
uniform float3 WarpTan = float3(0.7, 0.7, 1.7777);
// Set by the add-on: L4D2's camera position relative to Minecraft's, in Minecraft's camera space.
uniform float3 WarpT = float3(0.0, 0.0, 0.0);

// L4D2's picture at quarter size with mips: its blurred levels stand in for the light around each pixel.
texture GtaLightTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA8; MipLevels = 7; };
sampler sGtaLight { Texture = GtaLightTex; AddressU = CLAMP; AddressV = CLAMP; };

// The composited world (L4D2 + Minecraft, no overlay) and, per pixel: Minecraft's coverage, its depth and L4D2's.
texture CompositeTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA8; };
sampler sComposite { Texture = CompositeTex; AddressU = CLAMP; AddressV = CLAMP; };
texture McInfoTex { Width = BUFFER_WIDTH; Height = BUFFER_HEIGHT; Format = RGBA16F; };
sampler sMcInfo { Texture = McInfoTex; MinFilter = POINT; MagFilter = POINT; AddressU = CLAMP; AddressV = CLAMP; };
// Minecraft's bright parts at quarter size with mips (the glow).
texture McBrightTex { Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F; MipLevels = 6; };
sampler sMcBright { Texture = McBrightTex; AddressU = CLAMP; AddressV = CLAMP; };

float luma(float3 c)
{
	return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float4 PS_Light(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	return float4(tex2D(ReShade::BackBuffer, uv).rgb, 1.0);
}

/// Minecraft renders at full daylight, so treat its colour as albedo and light it with L4D2's local light; then give it
/// L4D2's colour grade (the whole picture's colour) and, far away, L4D2's haze (fade into the picture around it).
float3 relight(float3 c, float2 uv, float zm)
{
	const float3 L = tex2Dlod(sGtaLight, float4(uv, 0, LightBlur)).rgb;
	const float lum = luma(L);
	const float gain = clamp(lum / LightReference, 0.42, 1.3);
	const float3 tint = clamp(lerp(1.0, L / max(lum, 1e-3), LightTint), 0.55, 1.5);
	c = lerp(c, c * gain * tint, LightMatch);
	// the picture's grade, gentled (L4D2's own grade keeps some colour in everything) and kept off lights (bright
	// things keep their colour: fire, lava, the portal)
	const float3 M = tex2Dlod(sGtaLight, float4(0.5, 0.5, 0, 6.0)).rgb;
	const float3 grade = clamp(lerp(1.0, M / max(luma(M), 1e-3), 0.6), 0.6, 1.6);
	c = lerp(c, c * grade, GradeMatch * (1.0 - saturate((max(c.r, max(c.g, c.b)) - 0.45) * 2.5)));
	const float h = saturate((1.0 - exp(-max(zm - HazeStart, 0.0) / HazeDistance)) * HazeStrength);
	const float3 H = tex2Dlod(sGtaLight, float4(uv, 0, LightBlur + 1.0)).rgb;
	return lerp(c, H, h);
}

float mc_linear(float d)
{
	const float n = McPlanes.x, f = McPlanes.y;
	if (d <= 0.0)
		return 1e9;
	return n * f / (n + d * (f - n));
}

float host_linear(float d)
{
	const float n = HostPlanes.x, f = HostPlanes.y;
	float z;
	if (HostReversedZ)
		z = d > 0.0 ? n * f / (n + d * (f - n)) : 1e9;
	else
		z = d < 1.0 ? n * f / (f - d * (f - n)) : 1e9;
	return z * HostDepthScale;
}

float3 bands(float z)
{
	const float t = frac(z);
	return lerp(float3(0.1, 0.1, 0.1), float3(1.0, 0.85, 0.3), step(0.5, t)) * saturate(1.5 - z / 100.0);
}

// Track the surface already visible along the rotated guest ray before
// searching arbitrary distances. Sparse depth marching can skip a nearby
// cube completely when even a small camera translation changes its silhouette.
bool track_surface(float3 rotatedRay, float seed, float2 uv,
    out float2 candidate, out float hostDepth)
{
    const float2 scale=float2(WarpTan.y*WarpTan.z,WarpTan.y);
    candidate=0;hostDepth=1e9;
    float z=seed;
    [loop] for(int k=0;k<12;++k) {
        float3 p=rotatedRay*z+WarpT;
        if(p.z>=-0.001) return false;
        float2 ndc=p.xy/-p.z/scale;
        if(any(abs(ndc)>1)) return false;
        candidate=ndc*.5+.5;
        float depth=mc_linear(tex2Dlod(sDepth,float4(candidate,0,0)).r);
        if(depth>1e8) return false;
        z=(depth+WarpT.z)/max(-rotatedRay.z,0.000001);
    }
    float depth=mc_linear(tex2Dlod(sDepth,float4(candidate,0,0)).r);
    if(depth>1e8 || tex2Dlod(sWorld,float4(candidate,0,0)).a<0.005) return false;
    float3 q=float3((candidate*2-1)*scale,-1)*depth-WarpT;
    float3 hp=float3(dot(q,float3(WarpRow0.x,WarpRow1.x,WarpRow2.x)),
        dot(q,float3(WarpRow0.y,WarpRow1.y,WarpRow2.y)),
        dot(q,float3(WarpRow0.z,WarpRow1.z,WarpRow2.z)));
    if(hp.z>=-0.01) return false;
    float2 ndc=hp.xy/-hp.z/float2(WarpTan.x*BUFFER_WIDTH*BUFFER_RCP_HEIGHT,WarpTan.x);
    float2 error=(ndc-float2(uv.x*2-1,1-uv.y*2))*float2(BUFFER_WIDTH,BUFFER_HEIGHT)*.5;
    if(any(abs(error)>1.5)) return false;
    hostDepth=-hp.z;
    return true;
}

void PS_Composite(float4 pos : SV_Position, float2 uv : TEXCOORD, out float4 outColor : SV_Target0, out float4 outInfo : SV_Target1)
{
	const float3 host = tex2D(ReShade::BackBuffer, uv).rgb;
	outInfo = 0.0;
	outColor = float4(host, 1.0);
	if (!McActive)
		return;
	const float2 ouv = float2(uv.x, 1.0 - uv.y); // Minecraft's rows are bottom-up

    if (!HostOcclusion) {
        // True raw-color diagnostic: independent of BOTH depth buffers.
        float4 raw=tex2D(sWorld,ouv);
        outColor=float4(raw.rgb+host*(1-raw.a),1);
        outInfo=float4(raw.a,1,400,0);
        return;
    }

	// Where this L4D2 pixel's view ray lands in Minecraft's frame.
	float2 muv = ouv;
	bool inside = true;
	const float zh = HostOcclusion ? host_linear(tex2Dlod(ReShade::DepthBuffer, float4(uv, 0, 0)).x) : 400.0;
	// how far behind L4D2's surface Minecraft may still show: more where that surface is seen at a grazing angle
	const float allow = min(DepthBias + SlopeBias * abs(ddy(zh)), max(MaxBias, DepthBias));
	float zm = 1e9;
    const bool doWarp = Reproject && HostOcclusion; // Diagnostic bypass uses the untouched guest image.
    const float3 hostRay=float3((uv.x*2-1)*WarpTan.x*BUFFER_WIDTH*BUFFER_RCP_HEIGHT,(1-uv.y*2)*WarpTan.x,-1);
    const float3 rotatedRay=float3(dot(WarpRow0,hostRay),dot(WarpRow1,hostRay),dot(WarpRow2,hostRay));
    // Same eye position: rotation has an exact inverse projection. Ray marching
    // can miss a whole surface and is unnecessary in this common case.
    if (doWarp && dot(WarpT,WarpT)<0.000001) {
        float2 ndc=rotatedRay.xy/max(-rotatedRay.z,0.000001)/float2(WarpTan.y*WarpTan.z,WarpTan.y);
        muv=ndc*.5+.5;
        inside=rotatedRay.z<0 && all(abs(ndc)<=1);
        zm=mc_linear(tex2Dlod(sDepth,float4(muv,0,0)).r)/max(-rotatedRay.z,0.000001);
    }
    else if (doWarp)
    {
		// March this L4D2 pixel's ray (in L4D2's current camera) from near to far, moving each point into the
		// camera Minecraft rendered with (rotation + how far the camera moved since). The first point that is
		// behind Minecraft's surface there is where Minecraft is seen: refine it and sample. Thin, close things
		// (Steve in third person) are found even when the camera has swung sideways.
		const float3 ray = float3((uv.x * 2.0 - 1.0) * WarpTan.x * BUFFER_WIDTH * BUFFER_RCP_HEIGHT, (1.0 - uv.y * 2.0) * WarpTan.x, -1.0);
		const float2 mcScale = float2(WarpTan.y * WarpTan.z, WarpTan.y);
		const float zNear = 0.2;
		float2 ndc = 0.0;
        float2 rotatedNdc=rotatedRay.xy/max(-rotatedRay.z,0.000001)/mcScale;
        float seedDepth=mc_linear(tex2Dlod(sDepth,float4(rotatedNdc*.5+.5,0,0)).r);
        inside=rotatedRay.z<0 && all(abs(rotatedNdc)<=1) && seedDepth<1e8;
        if(inside) inside=track_surface(rotatedRay,(seedDepth+WarpT.z)/-rotatedRay.z,uv,muv,zm);
        const bool tracked=inside;
        const float2 trackedUv=muv;
        const float trackedDepth=zm;
        // A valid correspondence can still be a BACKGROUND surface. Search
        // nearer depths first; the tracked hit is the stable fallback, not an
        // excuse to bypass guest-versus-guest visibility ordering.
        const float zFar=max(min(min(zh+allow,400.0),tracked?trackedDepth:400.0),0.5);
        inside=false;
		[loop] for (int i = 0; i < 24 && !inside; ++i)
		{
			const float z = zNear * pow(zFar / zNear, i / 23.0);
			const float3 p = ray * z;
			const float3 pm = float3(dot(WarpRow0, p), dot(WarpRow1, p), dot(WarpRow2, p)) + WarpT;
			if (pm.z > -1e-3)
				continue;
			const float2 n = pm.xy / -pm.z / mcScale;
			if (any(abs(n) > 1.0))
				continue;
			const float zmv = mc_linear(tex2Dlod(sDepth, float4(n * 0.5 + 0.5, 0, 0)).r);
			if (zmv > -pm.z + 0.03)
				continue; // still in front of whatever Minecraft drew there
			// crossed Minecraft's surface: settle on it (fixed-point on the surface point's L4D2 depth)
			float zg = z;
			ndc = n;
			[loop] for (int k = 0; k < 12; ++k)
			{
				const float3 pk = ray * zg;
				const float3 mk = float3(dot(WarpRow0, pk), dot(WarpRow1, pk), dot(WarpRow2, pk)) + WarpT;
				if (mk.z > -1e-3)
					break;
				const float2 nk = mk.xy / -mk.z / mcScale;
				if (any(abs(nk) > 1.0))
					break;
				const float zk = mc_linear(tex2Dlod(sDepth, float4(nk * 0.5 + 0.5, 0, 0)).r);
				if (zk > 1e8)
					break;
				ndc = nk;
				const float3 q = float3(nk * mcScale, -1.0) * zk - WarpT;
				// Solve the sampled depth along the HOST ray directly. Back-projecting
                // an off-ray sample first couples x/y error into depth and can
                // oscillate between foreground/background surfaces.
                zg = (zk + WarpT.z) / max(-rotatedRay.z,0.000001);
			}
            // A depth discontinuity can make refinement jump to another block.
            // Accept only a surface point that projects back to THIS host pixel;
            // otherwise it produces the duplicate/floating cubes seen on turns.
            float2 candidate = ndc * 0.5 + 0.5;
            float depth = mc_linear(tex2Dlod(sDepth, float4(candidate,0,0)).r);
            float3 q = float3(ndc * mcScale,-1.0) * depth - WarpT;
            float3 hostPoint = float3(dot(q,float3(WarpRow0.x,WarpRow1.x,WarpRow2.x)),
                dot(q,float3(WarpRow0.y,WarpRow1.y,WarpRow2.y)),
                dot(q,float3(WarpRow0.z,WarpRow1.z,WarpRow2.z)));
            if (depth>1e8 || hostPoint.z>=-0.01 || tex2Dlod(sWorld,float4(candidate,0,0)).a<0.005) continue;
            float2 hostNdc=hostPoint.xy / -hostPoint.z / float2(WarpTan.x * BUFFER_WIDTH * BUFFER_RCP_HEIGHT,WarpTan.x);
            float2 errorPixels=(hostNdc-float2(uv.x*2-1,1-uv.y*2))*float2(BUFFER_WIDTH,BUFFER_HEIGHT)*0.5;
            if (any(abs(errorPixels)>1.5)) continue;
            muv=candidate;
            zm=-hostPoint.z;
            inside=true;
            break;
		}
        if(!inside && tracked) {muv=trackedUv;zm=trackedDepth;inside=true;}
	}
	const float4 world = inside ? tex2D(sWorld, muv) : 0.0;
	if (!doWarp)
		zm = mc_linear(tex2D(sDepth, muv).r);

	outInfo = float4(0.0, 0.0, zh, 0.0);
	if (DebugView == 1)
	{
		outColor = float4(bands(zh), 1.0);
		return;
	}
	if (DebugView == 2)
	{
		outColor = float4(world.a > 0.0 ? bands(zm) : host * 0.3, 1.0);
		return;
	}
	if (DebugView == 3)
	{
		outColor = float4(world.a > 0.0 ? float3(saturate((zh - zm) * 0.5 + 0.5), saturate(-(zh - zm) * 0.5 + 0.5), 0.0) : host * 0.3, 1.0);
		return;
	}

	const float visible = zm < zh + allow ? 1.0 : 0.0;
	const float cover = world.a * visible;
	outColor = float4(relight(world.rgb, uv, zm) * visible + host * (1.0 - cover), 1.0);
	outInfo = float4(cover, cover > 0.0 ? zm : 0.0, zh, 0.0);
}

/// Minecraft's bright parts (lava, fire, the portal, blazes): what glows.
float4 PS_Bright(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	const float cover = tex2D(sMcInfo, uv).x;
	const float3 c = tex2D(sComposite, uv).rgb;
	const float l = luma(c);
	return float4(c * (cover * saturate((l - BloomThreshold) / max(1.0 - BloomThreshold, 1e-3)) / max(l, 1e-3)), 1.0);
}

/// The finished picture: the world (shaken as one: L4D2 and Minecraft together), Minecraft's edges softened, contact
/// shadows on L4D2's surfaces next to Minecraft's, Minecraft's glow, the portal's warp, and Minecraft's hand and HUD on
/// top (neither shaken nor warped).
float3 PS_Final(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
	if (!McActive)
		return tex2D(ReShade::BackBuffer, uv).rgb;
	const float aspect = BUFFER_WIDTH * BUFFER_RCP_HEIGHT;
	const float t = Timer * 0.001;
	// shake: rotate and move the picture a little, zoomed in just enough that no edge shows
	const float amount = length(Shake.xy) + abs(Shake.z) * 0.5;
	const float zoom = 1.0 + amount * 2.2 + PortalWarp * 0.06;
	float2 d = (uv - 0.5) * float2(aspect, 1.0) / zoom;
	// the portal: a swirl and waves, strongest in the middle
	if (PortalWarp > 0.0)
	{
		const float r = length(d);
		const float swirl = PortalWarp * 1.1 * exp(-r * 2.2) * sin(t * 1.7 + 1.0);
		const float cs = cos(swirl), sn = sin(swirl);
		d = float2(d.x * cs - d.y * sn, d.x * sn + d.y * cs);
		d += PortalWarp * 0.014 * float2(sin(d.y * 38.0 + t * 7.0), cos(d.x * 31.0 + t * 6.0));
	}
	const float cr = cos(Shake.z), sr = sin(Shake.z);
	d = float2(d.x * cr - d.y * sr, d.x * sr + d.y * cr) + Shake.xy;
	const float2 wuv = d / float2(aspect, 1.0) + 0.5;

	const float2 px = BUFFER_PIXEL_SIZE;
	float3 color = tex2D(sComposite, wuv).rgb;
	const float4 info = tex2D(sMcInfo, wuv);
	// soften where Minecraft meets L4D2 (L4D2's anti-aliasing never saw Minecraft)
	if (EdgeSoftness > 0.0)
	{
		const float c1 = tex2D(sMcInfo, wuv + float2(px.x, 0)).x, c2 = tex2D(sMcInfo, wuv - float2(px.x, 0)).x;
		const float c3 = tex2D(sMcInfo, wuv + float2(0, px.y)).x, c4 = tex2D(sMcInfo, wuv - float2(0, px.y)).x;
		const float edge = saturate(abs(c1 - info.x) + abs(c2 - info.x) + abs(c3 - info.x) + abs(c4 - info.x));
		if (edge > 0.0)
		{
			const float3 n = tex2D(sComposite, wuv + float2(px.x, 0)).rgb + tex2D(sComposite, wuv - float2(px.x, 0)).rgb
				+ tex2D(sComposite, wuv + float2(0, px.y)).rgb + tex2D(sComposite, wuv - float2(0, px.y)).rgb;
			color = lerp(color, (color * 2.0 + n) / 6.0, edge * EdgeSoftness);
		}
	}
	// contact shadows: L4D2 surface pixels with Minecraft surfaces close by (in depth), mostly above them
	if (ContactShadow > 0.0 && info.x < 0.5 && info.z < 200.0)
	{
		const float zh = info.z;
		const float r = clamp(ContactRadius / max(zh, 0.5) * BUFFER_HEIGHT / (2.0 * WarpTan.x), 2.0, 48.0);
		float occ = 0.0, weight = 0.0;
		[unroll] for (int i = 0; i < 10; ++i)
		{
			const float a = i * 2.39996 + 0.6; // golden-angle spiral
			const float rr = r * sqrt((i + 0.5) / 10.0);
			const float2 o = float2(cos(a), sin(a)) * rr;
			const float4 sm = tex2Dlod(sMcInfo, float4(wuv + o * px, 0, 0));
			const float w = o.y < 0.0 ? 1.0 : 0.35; // things stand on the ground: their shadow is below them
			weight += w;
			if (sm.x > 0.5 && abs(sm.y - zh) < ContactRadius * 1.5)
				occ += w * (1.0 - rr / (r + 1.0));
		}
		color *= 1.0 - ContactShadow * saturate(occ / max(weight, 1e-3) * 2.2);
	}
	// Minecraft's glow
	if (BloomStrength > 0.0)
	{
		const float3 b = tex2Dlod(sMcBright, float4(wuv, 0, 1.0)).rgb * 0.5 + tex2Dlod(sMcBright, float4(wuv, 0, 2.5)).rgb * 0.8
			+ tex2Dlod(sMcBright, float4(wuv, 0, 4.0)).rgb;
		color += b * BloomStrength;
	}
	// the portal's purple
	if (PortalWarp > 0.0)
	{
		const float r = length((uv - 0.5) * float2(aspect, 1.0));
		const float3 purple = color * float3(0.72, 0.38, 1.25) + float3(0.12, 0.0, 0.22) * (0.6 + 0.4 * sin(t * 3.0 + r * 9.0));
		color = lerp(color, purple, saturate(PortalWarp * (0.55 + r * 0.6)));
	}
	const float4 overlay = tex2D(sOverlay, float2(uv.x, 1.0 - uv.y)); // hand and HUD are screen-space: never shaken
	return overlay.rgb + saturate(color) * (1.0 - overlay.a);
}

technique MCPassthrough < ui_tooltip = "Minecraft passthrough: enabled automatically while the Minecraft link is up."; >
{
	pass Light
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Light;
		RenderTarget = GtaLightTex;
	}
	pass Composite
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Composite;
		RenderTarget0 = CompositeTex;
		RenderTarget1 = McInfoTex;
	}
	pass Bright
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Bright;
		RenderTarget = McBrightTex;
	}
	pass Final
	{
		VertexShader = PostProcessVS;
		PixelShader = PS_Final;
	}
}
