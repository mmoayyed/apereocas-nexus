FROM sonatype/nexus3:3.91.0

USER root
COPY start.sh /opt/sonatype/start.sh
RUN chmod +x /opt/sonatype/start.sh && chown nexus:nexus /opt/sonatype/start.sh
USER nexus

CMD ["/opt/sonatype/start.sh"]