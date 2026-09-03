FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /app
COPY HelloWorld.java .
RUN javac --add-modules jdk.httpserver HelloWorld.java

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /app/HelloWorld.class .

EXPOSE 80
CMD ["java", "--add-modules", "jdk.httpserver", "HelloWorld"]