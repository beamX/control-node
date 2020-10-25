# Testing

## Generate example service_app
An example release tarball which can be run on the openssh-server can be prepared as
follows

```sh
cd example/
docker build -t beamx/openssh-server:erlang .
# Use above image to build a release for service_app
docker run -it -v $(pwd):/app  --entrypoint bash beamx/openssh-server:erlang
```

Inside Docker image

```
cd /app/service_app
MIX_ENV=prod mix release
exit
```

Copy tarball to the root parent folder

```
cd example/
cp service_app/_build/prod/service_app-0.1.0.tar.gz .
```


## Setup SSH keys

```sh
# client
ssh-keygen -t ed25519 -f ./id_ed25519 -C "control-node@email.com"

# deamon / remote host
ssh-keygen -t ed25519 -f ./ssh_host_ed25519_key -C "daemon@email.com"
```


## Start SSH server locally for testing

```sh
/usr/bin/sshd  -D -p 9191 -h $(pwd)/ssh_daemon/ssh_host_ed25519_key  -f $(pwd)/ssh_daemon/sshd_config  -o "AuthorizedKeysFile $(pwd)/host-vm/.ssh/authorized_keys"
```
