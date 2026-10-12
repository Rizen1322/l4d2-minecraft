package dev.rehan.passthrough.client;
import dev.rehan.passthrough.PeerRoster;
import net.minecraft.client.Minecraft;
import net.minecraft.client.multiplayer.ClientLevel;
import net.minecraft.client.entity.ClientMannequin;
import net.minecraft.client.resources.DefaultPlayerSkin;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EquipmentSlot;
import net.minecraft.world.entity.player.PlayerSkin;
import net.minecraft.world.item.ItemStack;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import java.util.HashMap;
import java.util.HashSet;

public final class PeerAvatars {
    private static ClientLevel level;
    private static long scene;
    private static final HashMap<Integer,PeerAvatar> avatars=new HashMap<>();
    private PeerAvatars(){}
    public static String pin(int entityId){for(var avatar:avatars.values())if(avatar.getId()==entityId)return avatar.member.pin();return "none";}
    public static boolean prone(int entityId){for(var avatar:avatars.values())if(avatar.getId()==entityId)return avatar.member.incap() || dev.rehan.passthrough.AvatarPosePolicy.prone(avatar.member.pin());return false;}
    public static boolean reviving(int entityId){for(var avatar:avatars.values())if(avatar.getId()==entityId)return HostState.peerReviving(avatar.member.id());return false;}
    public static void frame(){
        Minecraft mc=Minecraft.getInstance();var pose=HostState.frame();var roster=HostState.peerRoster();
        boolean live=pose!=null && roster!=null && roster.live(pose.scene(),System.nanoTime());
        if(level!=mc.level || !live || scene!=pose.scene()){
            if(level!=null)for(var avatar:avatars.values())if(level.getEntity(avatar.getId())==avatar)level.removeEntity(avatar.getId(),Entity.RemovalReason.DISCARDED);
            avatars.clear();level=mc.level;scene=pose==null?0:pose.scene();
        }
        if(!live || level==null)return;
        var wanted=new HashSet<Integer>();
        for(var member:roster.players()){
            if(member.dead())continue;
            wanted.add(member.id());
            PeerAvatar avatar=avatars.get(member.id());
            if(avatar==null){avatar=new PeerAvatar(level,mc);avatar.setId(member.entityId());avatar.setUUID(member.uuid(scene));avatars.put(member.id(),avatar);level.addEntity(avatar);}
            avatar.apply(member);
        }
        var remove=new java.util.ArrayList<Integer>();
        for(var entry:avatars.entrySet())if(!wanted.contains(entry.getKey()))remove.add(entry.getKey());
        for(int id:remove){var avatar=avatars.remove(id);if(level.getEntity(avatar.getId())==avatar)level.removeEntity(avatar.getId(),Entity.RemovalReason.DISCARDED);}
    }
    public static final class PeerAvatar extends ClientMannequin {
        public PeerRoster.Member member;
        private double lastX=Double.NaN,lastZ;
        private String main="",off="";
        private boolean equippedElytra;
        private int lastSwing=-1;
        private final dev.rehan.passthrough.MotionTrack motion=new dev.rehan.passthrough.MotionTrack();
        PeerAvatar(ClientLevel level,Minecraft mc){super(level,mc.playerSkinRenderCache());noPhysics=true;setNoGravity(true);setPermanentlyInvulnerable(true);}
        @Override public PlayerSkin getSkin(){return DefaultPlayerSkin.get(new java.util.UUID(0,15));}
        @Override public boolean isPickable(){return false;}
        @Override public boolean isPushable(){return false;}
        @Override public boolean canBeCollidedWith(Entity other){return false;}
        @Override public boolean canCollideWith(Entity other){return false;}
        @Override public void tick(){super.tick();if(member==null)return;float distance=Double.isNaN(lastX)?0:(float)Math.min(Math.hypot(getX()-lastX,getZ()-lastZ)*4,1);walkAnimation.update(distance,0.4F,1);lastX=getX();lastZ=getZ();}
        void apply(PeerRoster.Member peer){
            member=peer;long now=System.nanoTime();motion.observe(peer.x(),peer.y(),peer.z(),now);var pos=motion.sample(now);setPos(pos[0],pos[1],pos[2]);xo=xOld=pos[0];yo=yOld=pos[1];zo=zOld=pos[2];
            setYRot(peer.yaw());yRotO=peer.yaw();yBodyRot=yBodyRotO=yHeadRot=yHeadRotO=peer.yaw();setXRot(peer.pitch());xRotO=peer.pitch();
            setSharedFlag(FLAG_FALL_FLYING,peer.flying());
            setSharedFlagOnFire(peer.burning());
            if(!main.equals(peer.main())){main=peer.main();setItemSlot(EquipmentSlot.MAINHAND,item(main));}
            if(!off.equals(peer.off())){off=peer.off();setItemSlot(EquipmentSlot.OFFHAND,item(off));}
            if(lastSwing>=0 && peer.swing()>=0 && peer.swing()>lastSwing)swing(peer.swingHand().equals("off")?net.minecraft.world.InteractionHand.OFF_HAND:net.minecraft.world.InteractionHand.MAIN_HAND,net.minecraft.world.item.component.SwingAnimation.DEFAULT,true);
            lastSwing=peer.swing();
            var usingHand=peer.useHand().equals("off")?net.minecraft.world.InteractionHand.OFF_HAND:net.minecraft.world.InteractionHand.MAIN_HAND;
            if(peer.using()){if(!isUsingItem() || getUsedItemHand()!=usingHand){stopUsingItem();startUsingItem(usingHand);}}else if(isUsingItem())stopUsingItem();
            if(equippedElytra!=peer.flying()){
                equippedElytra=peer.flying();
                setItemSlot(EquipmentSlot.CHEST,equippedElytra?new ItemStack(net.minecraft.world.item.Items.ELYTRA):ItemStack.EMPTY);
            }
        }
        private static ItemStack item(String name){var item=BuiltInRegistries.ITEM.getValue(Identifier.parse(name));return item==null?ItemStack.EMPTY:new ItemStack(item);}
    }
}
