import logging
import os

from apiflask import APIFlask
from src import error, glog
from src.health import health_blueprint
from src.infinigram import infinigram_blueprint
from werkzeug.exceptions import HTTPException
from werkzeug.middleware.proxy_fix import ProxyFix


def create_app() -> ProxyFix:
    # If LOG_FORMAT is "google:json" emit log message as JSON in a format Google Cloud can parse.
    fmt = os.getenv("LOG_FORMAT")
    handlers = [glog.Handler()] if fmt == "google:json" else []
    level = os.environ.get("LOG_LEVEL", default=logging.INFO)
    logging.basicConfig(level=level, handlers=handlers)

    app = APIFlask(__name__, title="Infinigram API", version="0.1.0")
    app.register_blueprint(blueprint=health_blueprint, url_prefix="/health")
    app.register_blueprint(blueprint=infinigram_blueprint)
    app.register_error_handler(HTTPException, error.handle)

    # Use the X-Forwarded-* headers to set the request IP, host and port. Technically there
    # are two reverse proxies in deployed environments, but we "hide" the reverse proxy deployed
    # as a sibling of the API by forwarding the X-Forwarded-* headers rather than chaining them.
    return ProxyFix(app, x_for=1, x_proto=1, x_host=1, x_port=1)
