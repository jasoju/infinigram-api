import sys
import traceback

from apiflask import APIBlueprint, Schema, abort
from apiflask.fields import String

from src.infinigram.processor import processor

infinigram_blueprint = APIBlueprint(name="query_infinigram", import_name=__name__)


class InfinigramQuery(Schema):
    query = String(required=True)


@infinigram_blueprint.post("/query")
@infinigram_blueprint.input(InfinigramQuery)
def query(json_data):
    try:
        result = processor.find_docs_with_query(query=json_data["query"])

        return result
    except Exception as e:
        exc_type, exc_value, exc_traceback = sys.exc_info()
        traceback.print_exception(exc_type, exc_value, exc_traceback)
        abort(500, f"[Flask] Internal server error: {e}")
