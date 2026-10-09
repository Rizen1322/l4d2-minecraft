package dev.rehan.passthrough;
import java.util.function.Consumer;
/** ReentrantBlockableEventLoop otherwise requeues nested execute even on the server thread. */
public final class ServerDispatchPolicy {
    public static void run(boolean serverThread,Consumer<Runnable> schedule,Runnable action){
        if(serverThread)action.run();else schedule.accept(action);
    }
}
