FROM registry.fedoraproject.org/fedora:38

COPY slp-qemu-android-fedora-38.repo /etc/yum.repos.d/slp-qemu-android-fedora-38.repo

RUN dnf install -y qemu-system-x86 qemu-system-aarch64 virglrenderer rust-vhost-user-vsock
RUN mkdir -p /opt/start-avm/templates

COPY run_start_avm.sh /run_start_avm.sh
COPY start_cvd_tools /opt/start-avm/start_cvd_tools
COPY start_avm.sh /opt/start-avm/start_avm.sh
COPY templates/.cuttlefish_config.json /opt/start-avm/templates

CMD ["/bin/bash", "/run_start_avm.sh"]

