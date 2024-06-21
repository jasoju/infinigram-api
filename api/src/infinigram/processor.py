from infini_gram.engine import InfiniGramEngine
from transformers import AutoTokenizer, PreTrainedTokenizerBase


class InfiniGramProcessor:
    tokenizer: PreTrainedTokenizerBase
    infini_gram_engine: InfiniGramEngine

    def __init__(self):
        self.tokenizer = AutoTokenizer.from_pretrained(
            "./vendor/llama-2-7b-hf/", add_bos_token=False, add_eos_token=False
        )

        self.infini_gram_engine = InfiniGramEngine(
            index_dir="/mnt/infinigram-array", eos_token_id=self.tokenizer.eos_token_id
        )

    def find_docs_with_query(self, query: str):
        tokenized_query_ids = self.tokenizer.encode(query)
        return self.infini_gram_engine.search_docs(
            input_ids=tokenized_query_ids, maxnum=1, max_disp_len=10
        )


processor = InfiniGramProcessor()
