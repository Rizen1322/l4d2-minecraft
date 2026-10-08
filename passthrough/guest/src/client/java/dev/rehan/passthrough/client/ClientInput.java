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
import com.mojang.blaze3d.platform.InputConstants;
import net.minecraft.client.input.MouseButtonEvent;
import net.minecraft.client.input.MouseButtonInfo;
import dev.rehan.passthrough.client.mixin.MouseHandlerAccessor;
import net.minecraft.client.gui.screens.ChatScreen;
import net.minecraft.client.input.KeyEvent;
import net.minecraft.client.input.CharacterEvent;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.phys.EntityHitResult;
import net.minecraft.world.phys.BlockHitResult;
import java.util.Locale;

/** Host input, applied on the client thread: the host window has the focus, so Minecraft never sees these itself. */
final class ClientInput {
	private static double pointerX, pointerY;
    private static final dev.rehan.passthrough.ViewSizePolicy viewSize=new dev.rehan.passthrough.ViewSizePolicy();
	private ClientInput() {
	}
	static void releaseRelay(final Minecraft minecraft) {
		for (KeyMapping key : new KeyMapping[] {minecraft.options.keyUse,minecraft.options.keyAttack,
			minecraft.options.keyPickItem,minecraft.options.keyInventory,minecraft.options.keyDrop,minecraft.options.keySwapOffhand,minecraft.options.keyShift,minecraft.options.keySprint}) {
			key.setDown(false);
			((KeyMappingAccessor)key).passthrough$setClickCount(0);
		}
	}

	static void handle(final Minecraft minecraft, final JsonObject m) {
		LocalPlayer player = minecraft.player;
		switch (m.get("t").getAsString()) {
            case "guikey" -> {
                var screen=minecraft.gui.screen();
                if(screen==null)return;
                var event=new KeyEvent(m.get("scan").getAsInt(),m.get("code").getAsInt(),m.get("mods").getAsInt());
                if(m.get("down").getAsBoolean())screen.keyPressed(event);else screen.keyReleased(event);
            }
            case "text" -> {
                var screen=minecraft.gui.screen();
                if(screen!=null)for(int c:m.get("s").getAsString().codePoints().toArray())screen.charTyped(new CharacterEvent(c));
            }
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
					screen.mouseDragged(new MouseButtonEvent(x,y,new MouseButtonInfo(m.get("drag").getAsInt()==0?InputConstants.MOUSE_BUTTON_LEFT:InputConstants.MOUSE_BUTTON_RIGHT,m.has("mods")?m.get("mods").getAsInt():0)),x-pointerX,y-pointerY);
				pointerX=x; pointerY=y;
			}
			case "mouse" -> {
				var screen = minecraft.gui.screen();
				if (screen == null) return;
				int button = m.get("b").getAsInt()==0?InputConstants.MOUSE_BUTTON_LEFT:InputConstants.MOUSE_BUTTON_RIGHT;
                var event = new MouseButtonEvent(pointerX,pointerY,new MouseButtonInfo(button,m.has("mods")?m.get("mods").getAsInt():0));
				if (m.get("down").getAsBoolean()) screen.mouseClicked(event,false);
				else screen.mouseReleased(event);
			}
			case "key" -> {
				String k = m.get("k").getAsString();
				boolean down = !m.has("down") || m.get("down").getAsBoolean();
                    if (k.equals("chat") || k.equals("command")) {
                        if(down && player!=null && minecraft.gui.screen()==null)
                            minecraft.gui.setScreen(new ChatScreen(k.equals("command")?"/":"",false));
                        return;
                    }
					if (k.equals("escape")) {
					if (down && player != null) {
                        if(minecraft.gui.screen()!=null)minecraft.gui.screen().onClose();
                        // Escape belongs to Source; never open a second pause menu.
                        releaseRelay(minecraft);
					}

					return;
				}
				if (k.equals("inventory") && down && minecraft.gui.screen() != null) {
					minecraft.gui.screen().onClose();
					return;
				}

				if(k.equals("drop") && down && player!=null && m.has("mods") && (m.get("mods").getAsInt()&64)!=0) {
                    minecraft.gameMode.dropItem(player,true);return;
                }
                KeyMapping key = switch (k) {
					case "use" -> minecraft.options.keyUse;
					case "attack" -> minecraft.options.keyAttack;
					case "pick" -> minecraft.options.keyPickItem;
					case "inventory" -> minecraft.options.keyInventory;
					case "drop" -> minecraft.options.keyDrop;
					case "swap" -> minecraft.options.keySwapOffhand;
                    case "sneak" -> minecraft.options.keyShift;
                    case "sprint" -> minecraft.options.keySprint;
					default -> null;
				};
				if (k.equals("attack") && down && player != null && !(minecraft.hitResult instanceof EntityHitResult)) {
                    double strength=player.getAttackStrengthScale(0.5F);
                    double damage=player.getAttributeValue(Attributes.ATTACK_DAMAGE)*(0.2+strength*strength*0.8);
                    Passthrough.events.accept(String.format(Locale.ROOT,"{\"t\":\"melee\",\"d\":%.3f,\"r\":3.0,\"cut\":%b,\"tier\":%d}",damage,player.getMainHandItem().is(net.minecraft.tags.ItemTags.SWORDS),player.getMainHandItem().is(net.minecraft.world.item.Items.NETHERITE_SWORD)?2:player.getMainHandItem().is(net.minecraft.world.item.Items.DIAMOND_SWORD)?1:0));
                    player.resetAttackStrengthTicker();
				}
                if(k.equals("use") && down && player!=null && minecraft.gui.screen()==null
                        && (player.getMainHandItem().is(net.minecraft.world.item.Items.FLINT_AND_STEEL)
                            || player.getOffhandItem().is(net.minecraft.world.item.Items.FLINT_AND_STEEL))) {
                    var ground=HostState.surface();
                    boolean guestHit=minecraft.hitResult instanceof EntityHitResult
                        || (minecraft.hitResult instanceof BlockHitResult hit && !player.level().getBlockState(hit.getBlockPos()).isAir());
                    if(!guestHit && ground!=null && ground.face()==net.minecraft.core.Direction.UP && player.getEyePosition().distanceToSqr(ground.pos())<=25) {
                        dev.rehan.passthrough.SurvivalFeatures.igniteSurface(ground.pos().x,ground.pos().y,ground.pos().z);
                        return;
                    }
                }
                if(k.equals("use") && down && player!=null && HostState.canUse()
                        && !(minecraft.hitResult instanceof EntityHitResult)
                        && !(minecraft.hitResult instanceof BlockHitResult hit && !player.level().getBlockState(hit.getBlockPos()).isAir())) {
                    if(!HostState.nativeUse())Passthrough.events.accept("{\"t\":\"interact\"}");
                    return; // Source door/button consumes this click before placing an item.
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
                if(minecraft.gui.screen()!=null) {
                    minecraft.gui.screen().mouseScrolled(pointerX,pointerY,0,m.get("d").getAsDouble());
                    return;
                }
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
                // Idempotent: reconnects must not restore/resize a matching window.
				int w = m.get("w").getAsInt(), h = m.get("h").getAsInt();
                if(!viewSize.accept(w,h,minecraft.getWindow().getScreenWidth(),minecraft.getWindow().getScreenHeight()))return;
                minecraft.getWindow().setWindowed(w,h);
			}
			default -> {
			}
		}
	}
}
