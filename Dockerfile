FROM grafana/grafana:6.7.1

COPY datasources.yaml /etc/grafana/provisioning/datasources/
COPY dashboards.yaml /etc/grafana/provisioning/dashboards/
COPY sample-dashboards/*.json /var/lib/grafana/dashboards/

USER root
RUN chown -R grafana:grafana /etc/grafana/provisioning
RUN chown -R grafana:grafana /var/lib/grafana/
USER grafana