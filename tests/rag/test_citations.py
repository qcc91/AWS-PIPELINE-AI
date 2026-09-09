import pytest

from src.rag.citations import build_cited_answer, validate_citations


def test_build_cited_answer_is_grounded_and_attributable():
    result = build_cited_answer(
        "The waiting period is 14 days.",
        [{"title": "Claims guide", "uri": "s3://docs/rag/approved/claims.md"}],
    )
    assert "Sources:" in result
    assert "[1] Claims guide" in result
    assert validate_citations(result, ["s3://docs/rag/approved/claims.md"])


def test_rejects_uncited_answer():
    with pytest.raises(ValueError):
        build_cited_answer("An unsupported answer", [])


def test_rejects_non_s3_source():
    with pytest.raises(ValueError):
        build_cited_answer("Answer", [{"uri": "https://example.invalid/doc"}])
