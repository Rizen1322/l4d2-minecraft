package dev.rehan.passthrough;

import java.util.*;
import java.util.function.ToDoubleFunction;

/** Stable nearest K with one distance evaluation per candidate and O(K) storage. */
public final class NearestLimit {
    private NearestLimit(){}
    private record Candidate<T>(T value,double distance,long order){}
    public static <T> List<T> select(Iterable<T> input,int limit,ToDoubleFunction<T> distance){
        if(limit<=0)return List.of();
        Comparator<Candidate<T>> cmp=Comparator.comparingDouble((Candidate<T> c)->c.distance).thenComparingLong(c->c.order);
        var heap=new PriorityQueue<Candidate<T>>(limit,cmp.reversed());long order=0;
        for(T value:input){
            double d=distance.applyAsDouble(value);long ordinal=order++;
            if(heap.size()==limit && Double.compare(d,heap.peek().distance)>=0)continue;
            if(heap.size()==limit)heap.poll();heap.add(new Candidate<>(value,d,ordinal));
        }
        var sorted=new ArrayList<>(heap);sorted.sort(cmp);var result=new ArrayList<T>(sorted.size());
        for(var c:sorted)result.add(c.value);return result;
    }
}
