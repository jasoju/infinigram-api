import asyncio
import os
from typing import Any

import numpy as np
from infini_gram_processor import indexes
from infini_gram_processor.index_mappings import AvailableInfiniGramIndexId
from infini_gram_processor.models import (
    SpanRankingMethod,
)
from infini_gram_processor.models.models import (
    AttributionResponse,
    AttributionSpan,
)
from .config import get_config
from .get_documents import (
    get_document_requests,
    get_spans_with_documents,
    sort_and_cap_spans,
)


# load configuration
config = get_config()



# main worker that performs the attribution
async def attribution_job(
    *,
    index: str,
    input: str,
    delimiters: list[str],
    allow_spans_with_partial_words: bool,
    minimum_span_length: int,
    maximum_frequency: int,
    maximum_span_density: float,
    span_ranking_method: SpanRankingMethod,
    maximum_context_length: int,
    maximum_context_length_long: int,
    maximum_context_length_snippet: int,
    maximum_documents_per_span: int,
) -> str:
        # get index (from list of all availiable indixes by index id)
        infini_gram_index = indexes[AvailableInfiniGramIndexId(index)]

        # extract spans of text
        attribute_result = await asyncio.to_thread(
            infini_gram_index.attribute,
            input=input,
            delimiters=delimiters,
            allow_spans_with_partial_words=allow_spans_with_partial_words,
            minimum_span_length=minimum_span_length,
            maximum_frequency=maximum_frequency,
        )

        # Limit the density of spans, and keep the longest ones
        # calculates maximum number of spans depending on length of input (in number of tokens) and a predefined maximum_span_density value (float)
        maximum_num_spans = int(
            np.ceil(len(attribute_result.input_token_ids) * maximum_span_density)
        )

        # sort spans by either LENGTH or UNIGRAM_LOGPROB_SUM
        # and only returns max number of spans in the form of a list
        sorted_spans = sort_and_cap_spans(
            attribute_result.spans,
            ranking_method=span_ranking_method,
            maximum_num_spans=maximum_num_spans,
        )

        # get all documents pointers for each span
        document_request_by_span = get_document_requests(
            spans=sorted_spans,
            input_token_ids=attribute_result.input_token_ids,
            maximum_documents_per_span=maximum_documents_per_span,
            maximum_context_length=maximum_context_length,
        )

        # retrieve actual texts for each document pointer
        documents_by_span = await asyncio.to_thread(
            infini_gram_index.get_documents_by_pointers,
            document_request_by_span=document_request_by_span,
        )

        # put documents to spans 
        # function joins together: raw spans, documents, decoded text of those documents
        # function joins together: raw spans, documents, decoded text of those documents
        spans_with_documents: list[AttributionSpan] = get_spans_with_documents(
            infini_gram_index=infini_gram_index,
            spans=sorted_spans,
            documents_by_span=documents_by_span,
            input_token_ids=attribute_result.input_token_ids,
            maximum_context_length_long=maximum_context_length_long,
            maximum_context_length_snippet=maximum_context_length_snippet,
        )

        # create response and pack everything into a json 
        response = AttributionResponse(
            index=infini_gram_index.index,
            spans=spans_with_documents,
            input_tokens=infini_gram_index.tokenize_to_list(input),
        )
        return response.model_dump_json()
