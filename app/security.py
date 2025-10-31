"""
Security utilities for the ML platform.

This module provides security-related utility functions, including
file integrity verification via cryptographic hashing.
"""

import hashlib
from pathlib import Path


def calculate_file_hash(filepath: Path, algorithm: str = "sha256") -> str:
    """
    Calculate cryptographic hash of a file.

    This function computes the hash of a file by reading it in chunks,
    making it suitable for large files. The default algorithm is SHA-256,
    which provides strong collision resistance for integrity verification.

    Args:
        filepath: Path to the file to hash
        algorithm: Hash algorithm to use (default: sha256)
                  Must be a valid hashlib algorithm (e.g., sha256, sha512, md5)

    Returns:
        Hexadecimal string representation of the hash

    Raises:
        FileNotFoundError: If the file does not exist
        ValueError: If the algorithm is not supported

    Example:
        >>> from pathlib import Path
        >>> hash_value = calculate_file_hash(Path("model.joblib"))
        >>> len(hash_value)  # SHA-256 produces 64 hex characters
        64
    """
    hash_obj = hashlib.new(algorithm)
    with open(filepath, "rb") as f:
        # Read in chunks to handle large files efficiently
        for byte_block in iter(lambda: f.read(4096), b""):
            hash_obj.update(byte_block)
    return hash_obj.hexdigest()
