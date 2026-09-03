# Docker Hello World Applications

Each folder contains one independent application and its Dockerfile.

Build and run an application from its folder, for example:

```bash
cd "node-application"
docker build -t hello-node .
docker run --rm -p 8081:80 hello-node
```

Open `http://localhost:8081` in a browser. Use a different host port for
each application if running more than one at a time.

| Folder | Image example | Host port |
| --- | --- | --- |
| `node-application` | `hello-node` | `8081` |
| `python-application` | `hello-python` | `8082` |
| `java-application` | `hello-java` | `8083` |
| `apache-application` | `hello-apache` | `8084` |
| `react-application` | `hello-react` | `8085` |
| `nginx-application` | `hello-nginx` | `8086` |