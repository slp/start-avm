FROM registry.fedoraproject.org/fedora:38

COPY slp-qemu-android-fedora-38.repo /etc/yum.repos.d/slp-qemu-android-fedora-38.repo

RUN dnf install -y qemu-system-x86 qemu-system-aarch64 virglrenderer vhost-user-vsock cvd2img openssl

COPY run_start_avm.sh start_cvd_tools start_avm.sh /opt/start-avm/
COPY templates /opt/start-avm/templates/

CMD ["/bin/bash", "/opt/start-avm/run_start_avm.sh"]
