import sys
import traceback

from apiflask import APIBlueprint, Schema, abort
from apiflask.fields import String

from src.infinigram.processor import PROCESSOR_BY_INDEX

infinigram_blueprint = APIBlueprint(name="query_infinigram", import_name=__name__)


class InfinigramQueryOutput(Schema):
    foo = String()


class InfinigramQuery(Schema):
    query = String(required=True)


@infinigram_blueprint.post("/query")
@infinigram_blueprint.input(InfinigramQuery)
@infinigram_blueprint.output(InfinigramQueryOutput)
def query(data):
    print(data)

    try:
        query_type = data["query_type"]
        index = data["corpus"] if "corpus" in data else data["index"]

        for key in ["query_type", "corpus", "index", "engine", "source", "timestamp"]:
            if key in data:
                del data[key]

        if ("query" not in data and "query_ids" not in data) or (
            "query" in data and "query_ids" in data
        ):
            abort(400, "[Flask] Exactly one of query and query_ids must be present!")

        if "query" in data:
            query = data["query"]
            query_ids = None
            del data["query"]
        else:
            query = None
            query_ids = data["query_ids"]
            del data["query_ids"]

    except KeyError as e:
        abort(400, f"[Flask] Missing required field: {e}")

    try:
        processor = PROCESSOR_BY_INDEX[index]
    except KeyError:
        abort(400, f"[Flask] Invalid index: {index}")

    if not hasattr(processor.engine, query_type):
        abort(400, f"[Flask] Invalid query_type: {query_type}")

    try:
        result = processor.process(query_type, query, query_ids, **data)

        return result
    except Exception as e:
        exc_type, exc_value, exc_traceback = sys.exc_info()
        traceback.print_exception(exc_type, exc_value, exc_traceback)
        abort(500, f"[Flask] Internal server error: {e}")
