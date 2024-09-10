### How to rebuild service_app

``` sh
docker run -v ./service_app:/app -it elixir:1.14.5-otp-24-alpine sh

$ cd /app && MIX_ENV=prod mix release --overwrite 
$ exit

cp service_app/_build/prod/service_app-0.1.0.tar.gz .
sudo rm -rf service_app/_build
```
