FROM --platform=linux/amd64 chillfraestrcuture/p2mstoragemanager:1.0.0

# Exponer puerto
EXPOSE 8080

# Configurar variables de entorno
ENV LOG_LEVEL=info \
    SWIFT_REPLICAS=3 \
    WORKERS=auto \
    SWIFT_USERNAME= \
    SWIFT_PASSWORD=

# Punto de montaje para volumen persistente
VOLUME ["/srv"]

# Ejecutar servidor Swift al iniciar el contenedor
CMD ["/bin/sh", "-c", "which swift-init && /path/to/swift-init all restart && /path/to/swift-init all status && tail -f /dev/null"]