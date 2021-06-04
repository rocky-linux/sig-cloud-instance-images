FROM scratch
ADD Rocky-8.4-RC1-20210604.x86_64.tar.xz  /

LABEL org.label-schema.schema-version="1.0" \
    org.label-schema.name="Rocky Linux Base Image" \
    org.label-schema.vendor="Rocky Enterprise Software Foundation" \
    org.label-schema.license="BSD-3-Clause" \
    org.label-schema.build-date="20210604" \
    org.opencontainers.image.title="Rocky Linux Base Image" \
    org.opencontainers.image.vendor="Rocky Enterprise Software Foundation" \
    org.opencontainers.image.licenses="BSD-3-Clause" \
    org.opencontainers.image.created="2021-06-04 00:00:00+01:00"

CMD ["/bin/bash"]
