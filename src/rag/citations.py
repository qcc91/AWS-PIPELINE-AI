"""Keep Bedrock RetrieveAndGenerate responses attributable to source chunks."""

from collections.abc import Iterable, Mapping


def build_cited_answer(answer: str, citations: Iterable[Mapping[str, object]]) -> str:
    """Append stable [n] markers and a compact source list to a generated answer.

    The caller supplies Bedrock citation objects (or normalized dictionaries)
    and remains responsible for generating the answer. Empty citations are
    rejected so a response cannot be presented as grounded accidentally.
    """
    rows = list(citations)
    if not answer.strip() or not rows:
        raise ValueError("a non-empty answer and at least one citation are required")
    sources = []
    for number, citation in enumerate(rows, 1):
        uri = str(citation.get("uri", "")).strip()
        title = str(citation.get("title", uri or f"source-{number}")).strip()
        if not uri.startswith("s3://"):
            raise ValueError("citation uri must be an s3:// URI")
        sources.append(f"[{number}] {title} — {uri}")
    return f"{answer.rstrip()}\n\nSources:\n" + "\n".join(sources)


def validate_citations(response: str, expected_uris: Iterable[str]) -> bool:
    """Return true only when every expected source URI is present in response."""
    return bool(response.strip()) and all(uri in response for uri in expected_uris)
