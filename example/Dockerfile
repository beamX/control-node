# Deprecated, not used anymore but was an attempt to
# - install nix in docker
# - install elixir using nix
# - build elixir service
# The issue is that the build fails to run because the during build the executables generated source their sh path from nix store i.e.
#
# for eg.  #!/nix/store/7mbf4p3z7pyvpha1fwv29n1cw0ms65wg-nix-something/sh
#
# so the release tar cannot be deployed to a target host since these paths do not exist there

FROM  elixir:1.14.5-otp-24-alpine

RUN curl -L https://nixos.org/nix/install > /tmp/nix.install

RUN sh /tmp/nix.install --daemon

RUN cp /etc/bashrc /root/.bashrc

ENV LANG=C.UTF-8
USER root
RUN /root/.nix-profile/bin/nix-env -iA nixpkgs.elixir_1_14

CMD ["iex"]
