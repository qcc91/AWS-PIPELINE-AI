from pathlib import Path


MODULE = (Path(__file__).parents[2] / "terraform" / "modules" / "ml" / "main.tf").read_text(
    encoding="utf-8"
)


def test_glue_role_can_read_its_postprocess_script():
    assert '${local.control_arn}/artifacts/ml/*' in MODULE


def test_v1_ml_has_no_persistent_compute_resources():
    forbidden = (
        'resource "aws_sagemaker_endpoint"',
        'resource "aws_sagemaker_endpoint_configuration"',
        'resource "aws_sagemaker_notebook_instance"',
    )
    assert not any(resource in MODULE for resource in forbidden)
