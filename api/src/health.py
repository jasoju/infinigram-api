from typing import Tuple

from apiflask import APIBlueprint

health_blueprint = APIBlueprint(name="health", import_name=__name__)


# This tells the machinery that powers Skiff (Kubernetes) that your application
# is ready to receive traffic. Returning a non 2XX response code will prevent the
# application from receiving live requests.
@health_blueprint.get("/")
def health() -> Tuple[str, int]:
    return "", 204
