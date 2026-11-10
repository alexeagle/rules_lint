from dependency import greet
from stub import stub_greet

greet(42)
wrong_type: int = stub_greet("World")
