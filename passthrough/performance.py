"""Guest-only performance presets; Source resolution and camera aspect stay intact."""
PRESETS={'quality':(1.0,260),'balanced':(.75,90),'low':(.5,60)}

def guest_view(width,height,profile='quality'):
    if type(width) is not int or type(height) is not int or not 320<=width<=3840 or not 240<=height<=2160:
        raise ValueError('Unsupported output resolution')
    scale,fps=PRESETS[profile]
    scale=max(scale,320/width,240/height)
    return {'t':'view','w':round(width*scale),'h':round(height*scale),'fps':fps,'lowfx':profile=='low'}
