from attribution_worker.worker import attribution_job
from infini_gram_processor.models import (
    SpanRankingMethod,
)

span_ranking_method = SpanRankingMethod.LENGTH

response = attribution_job(
    index="pileval-llama",
    input="As a black woman, I am a unique and multifaceted individual. My skin is a rich, deep shade of brown, and my hair is a crowning glory in its natural state—kinky, curly, or coily. My features reflect the beauty and strength of my African ancestry, with full lips and a broad nose. I am proud of my heritage and the diversity it brings to my identity. I am educated and informed, with a passion for social justice and equality. As a black woman, I am resilient, having faced and overcome various challenges throughout my life. Despite the systemic barriers and stereotypes that society has imposed, I have cultivated a strong sense of self and a profound level of empathy that guides my interactions with others. My style is bold and expressive, a reflection of my vibrant personality and the richness of my culture. My strength, resilience, and beauty are not only my own, but they also represent the strength, resilience, and beauty of my community. I am a black woman, unapologetically myself, and I am proud.",
    delimiters=["."],
    allow_spans_with_partial_words=False,
    minimum_span_length=10,
    maximum_frequency= 10,
    maximum_span_density= 0.5,
    span_ranking_method=span_ranking_method,
    maximum_context_length= 10,
    maximum_context_length_long= 10,
    maximum_context_length_snippet= 5,
    maximum_documents_per_span= 2
)

print(response)