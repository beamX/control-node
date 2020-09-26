An example release tar which can be run on the openssh-server can be prepared as
follows

```sh
cd example/
docker build -t beamx/openssh-server:erlang .
# Use above image to build a release for service_app
docker run -it -v $(pwd):/app  --entrypoint bash beamx/openssh-server:erlang
```

Inside docker image
```
cd /app/service_app
MIX_ENV=prod mix release
exit
```

copy tar to the root parent folder
```
cd example/
cp service_app/_build/prod/service_app-0.1.0.tar.gz .
```
