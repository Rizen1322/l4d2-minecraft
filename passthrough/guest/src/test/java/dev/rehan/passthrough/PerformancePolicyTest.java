package dev.rehan.passthrough;

public final class PerformancePolicyTest {
    public static void main(String[] args){
        var index=new LoadedEntityIndex<Object>();var old=new Object();var replacement=new Object();
        index.load(7,old);index.load(7,replacement);index.unload(7,old);
        if(!index.values().contains(replacement))throw new AssertionError("Old unload removed reused ID");
        index.unload(7,replacement);if(!index.values().isEmpty())throw new AssertionError("Unload leaked entity");
        index.load(8,old);index.clear();if(!index.values().isEmpty())throw new AssertionError("World reset leaked entities");
        var cache=new CollisionCachePolicy();Object world=new Object();String bounds="0,0,0,32,64,32";
        if(cache.reusable(world,1,0,bounds,0))throw new AssertionError("Uninitialized cache");
        cache.store(world,1,5,bounds,10);
        if(!cache.reusable(world,1,5,bounds,999_999_999L))throw new AssertionError("Complete stationary snapshot not reused");
        if(cache.reusable(world,1,6,bounds,20))throw new AssertionError("Block edit not invalidated");
        if(cache.reusable(world,2,5,bounds,20))throw new AssertionError("Chapter not invalidated");
        if(cache.reusable(new Object(),1,5,bounds,20))throw new AssertionError("Server world not invalidated");
        if(cache.reusable(world,1,5,"1,0,0,33,64,32",20))throw new AssertionError("Movement not invalidated");
        if(cache.reusable(world,1,5,bounds,1_000_000_010L))throw new AssertionError("Audit deadline not enforced");
        if(cache.reusable(world,1,5,bounds,9))throw new AssertionError("Clock regression");
        cache.clear();if(cache.reusable(world,1,5,bounds,20))throw new AssertionError("Reset not invalidated");
        var random=new java.util.Random(1907);
        for(int n:new int[]{0,1,63,64,65,5000}){
            var rows=new java.util.ArrayList<Integer>();for(int i=0;i<n;i++)rows.add(random.nextInt(100));
            var expected=new java.util.ArrayList<>(rows);expected.sort(java.util.Comparator.comparingDouble(v->v%17));
            expected=new java.util.ArrayList<>(expected.subList(0,Math.min(64,n)));
            int[] evaluations={0};var selected=NearestLimit.select(rows,64,v->{evaluations[0]++;return v%17;});
            if(!selected.equals(expected))throw new AssertionError("Nearest K changed ties/order at "+n);
            if(evaluations[0]!=n)throw new AssertionError("Distance evaluated repeatedly");
        }
        if(!NearestLimit.select(java.util.List.of(1,2),0,v->v).isEmpty())throw new AssertionError("Empty limit");
        System.out.println("Performance cache and entity lifecycle regressions passed");
    }
}
