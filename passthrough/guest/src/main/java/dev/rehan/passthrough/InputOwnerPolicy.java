package dev.rehan.passthrough;
/** Ownership never carries across connections; cleanup may carry across map changes. */
public final class InputOwnerPolicy {
    public static boolean accept(boolean controller,long queuedGeneration,long generation,long queuedScene,long scene,boolean cleanup){
        return controller && queuedGeneration==generation && (cleanup || queuedScene==scene);
    }
}
