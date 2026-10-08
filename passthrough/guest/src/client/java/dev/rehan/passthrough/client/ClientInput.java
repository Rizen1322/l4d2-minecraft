package dev.rehan.passthrough.client;

import com.google.gson.JsonObject;
import dev.rehan.passthrough.Passthrough;
import dev.rehan.passthrough.client.mixin.KeyMappingAccessor;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.entity.player.Inventory;
import org.lwjgl.sdl.SDLVideo;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.client.input.MouseButtonInfo;
import dev.rehan.passthrough.client.mixin.MouseHandlerAccessor;

/** Host input, applied on the client thread: the host window has the focus, so Minecraft never sees these itself. */
final class ClientInput {
	private static double pointerX, pointerY;
	private ClientInput() {
	}
	static void releaseRelay(final Minecraft minecraft) {
		for (KeyMapping key : new KeyMapping[] {minecraft.options.keyUse,minecraft.options.keyAttack,
			minecraft.options.keyPickItem,minecraft.options.keyInventory,minecraft.options.keyDrop,minecraft.options.keySwapOffhand}) {
			key.setDown(false);
			((KeyMappingAccessor)key).passthrough$setClickCount(0);
		}
	}

	static void handle(final Minecraft minecraft, final JsonObject m) {
		LocalPlayer player = minecraft.player;
		switch (m.get("t").getAsString()) {
			case "pointer" -> {
				var screen = minecraft.gui.screen();
				if (screen == null) return;
				double x = Math.clamp(m.get("x").getAsDouble(), 0.0, 1.0) * minecraft.getWindow().getGuiScaledWidth();
				double y = Math.clamp(m.get("y").getAsDouble(), 0.0, 1.0) * minecraft.getWindow().getGuiScaledHeight();
				var mouse = (MouseHandlerAccessor)minecraft.mouseHandler;
				mouse.l4d2mc$setX(m.get("x").getAsDouble()*minecraft.getWindow().getScreenWidth());
				mouse.l4d2mc$setY(m.get("y").getAsDouble()*minecraft.getWindow().getScreenHeight());
				screen.mouseMoved(x, y);
				if (m.has("drag") && m.get("drag").getAsInt() >= 0)
					screen.mouseDragged(new MouseButtonEvent(x,y,new MouseButtonInfo(m.get("drag").getAsInt(),0)),x-pointerX,y-pointerY);
				pointerX=x; pointerY=y;
			}
			case "mouse" -> {
				var screen = minecraft.gui.screen();
				if (screen == null) return;
				int button = Math.clamp(m.get("b").getAsInt(),0,1);
				var event = new MouseButtonEvent(pointerX,pointerY,new MouseButtonInfo(button,0));
				if (m.get("down").getAsBoolean()) screen.mouseClicked(event,false);
				else screen.mouseReleased(event);
			}
			case "key" -> {
				String k = m.get("k").getAsString();
				boolean down = !m.has("down") || m.get("down").getAsBoolean();
					if (k.equals("escape")) {
					if (down && player != null && minecraft.gui.screen() != null) {
						minecraft.gui.screen().onClose();
					}

					return;
				}
				if (k.equals("inventory") && down && minecraft.gui.screen() != null) {
					minecraft.gui.screen().onClose();
					return;
				}

				KeyMapping key = switch (k) {
					case "use" -> minecraft.options.keyUse;
					case "attack" -> minecraft.options.keyAttack;
					case "pick" -> minecraft.options.keyPickItem;
					case "inventory" -> minecraft.options.keyInventory;
					case "drop" -> minecraft.options.keyDrop;
					case "swap" -> minecraft.options.keySwapOffhand;
					default -> null;
				};
				if (k.equals("attack") && down && player != null
					&& BuiltInRegistries.ITEM.getKey(player.getMainHandItem().getItem()).getPath().endsWith("_sword")) {
					// a sword swing: the host hits what's in front of Steve in its own world
					Passthrough.events.accept("{\"t\":\"melee\"}");
				}

				if (key != null) {
					if (down && !key.isDown()) {
						KeyMappingAccessor access = (KeyMappingAccessor)key;
						access.passthrough$setClickCount(access.passthrough$getClickCount() + 1);
					}

					key.setDown(down);
				}
			}
			case "slot" -> {
				if (player != null) {
					player.getInventory().setSelectedSlot(Math.clamp(m.get("n").getAsInt(), 0, Inventory.getSelectionSize() - 1));
				}
			}
			case "scroll" -> {
				if (player != null) {
					Inventory inventory = player.getInventory();
					int size = Inventory.getSelectionSize();
					inventory.setSelectedSlot(Math.floorMod(inventory.getSelectedSlot() - m.get("d").getAsInt(), size));
				}
			}
			case "hud" -> {
				if (minecraft.gui.hud.isHidden() != m.get("hidden").getAsBoolean()) {
					minecraft.gui.hud.toggle();
				}
			}
			case "view" -> {
				// match the host's picture exactly: un-minimize/un-maximize first (resizing a maximized window is ignored)
				int w = m.get("w").getAsInt(), h = m.get("h").getAsInt();
				long handle = minecraft.getWindow().handle();
				SDLVideo.SDL_RestoreWindow(handle);
				minecraft.getWindow().setWindowed(w, h);
				SDLVideo.SDL_SetWindowSize(handle, w, h);
				SDLVideo.SDL_SyncWindow(handle);
			}
			default -> {
			}
		}
	}
}
