# from time import sleep


# def test_debug(host):
#     sleep(5000) # Handy for interactive debugging (with docker exec -it $CONTAINER_ID /bin/bash)


def test_logrotate_timer(host):
    timer = host.service("logrotate.timer")
    assert timer.is_enabled
    assert timer.is_running


def test_logrotate_service_unit(host):
    svc = host.service("logrotate.service")
    assert svc.is_valid
    result = host.run("systemctl start logrotate.service")
    assert result.rc == 0


def test_logrotate_configs(host):
    for fname in [
        "/etc/logrotate.d/logrotate-postgres-auth.conf",
        "/etc/logrotate.d/logrotate-postgres-csv.conf",
        "/etc/logrotate.d/logrotate-postgres.conf",
        "/etc/logrotate.d/logrotate-walg.conf",
    ]:
        f = host.file(fname)
        assert f.exists
        assert f.user == "root"
