from src.generated_native import greet


def main() -> None:
    message: str = greet("World")
    print(message)
