import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public class HelloWorld {
    public static void main(String[] args) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress(80), 0);
        server.createContext("/", HelloWorld::respond);
        server.start();
        System.out.println("Java app listening on port 80");
    }

    private static void respond(HttpExchange exchange) throws IOException {
        byte[] body = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>Hello World</title></head><body><h1>Hello World from Java</h1></body></html>"
                .getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
        exchange.sendResponseHeaders(200, body.length);
        exchange.getResponseBody().write(body);
        exchange.close();
    }
}