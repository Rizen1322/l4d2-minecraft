package dev.rehan.passthrough;

public final class ProjectileOriginsTest {
    public static void main(String[] args) {
        var launches = new ProjectileOrigins();
        var first = launches.remember(7, 0, 2, 0);
        if (!first.equals(launches.remember(7, 15, 2, 0)))
            throw new AssertionError("Coalescing erased the launch segment");
        launches.retain(java.util.Set.of(8));
        if (!launches.remember(7, 20, 3, 0).equals(new ProjectileOrigins.Point(20, 3, 0)))
            throw new AssertionError("Removed projectile retained a reused entity id");
        launches.clear();
        if (!launches.remember(7, 40, 4, 0).equals(new ProjectileOrigins.Point(40, 4, 0)))
            throw new AssertionError("Scene reset retained old launches");
        System.out.println("Projectile launch retention regressions passed");
    }
}
