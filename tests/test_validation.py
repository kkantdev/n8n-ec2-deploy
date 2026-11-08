#!/usr/bin/env python3
"""
Unit tests for validation functions:
- Domain validation
- Email validation
- IPv4 address validation
- Port validation
- PostgreSQL connection string parsing
"""

import re
import unittest

def validate_domain(domain: str) -> bool:
    if not domain or "://" in domain or "/" in domain or ":" in domain:
        return False
    regex = r"^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"
    return bool(re.match(regex, domain))

def validate_email(email: str) -> bool:
    regex = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    return bool(re.match(regex, email))

def validate_ipv4(ip: str) -> bool:
    regex = r"^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    if not re.match(regex, ip):
        return False
    octets = ip.split(".")
    for octet in octets:
        val = int(octet)
        if val < 0 or val > 255:
            return False
    return True

def validate_port(port_val) -> bool:
    try:
        val = int(port_val)
        return 1 <= val <= 65535
    except (ValueError, TypeError):
        return False

def parse_postgres_uri(uri: str):
    scheme_match = re.match(r"^(postgres|postgresql)://", uri)
    if not scheme_match:
        return None
    clean = uri[scheme_match.end():]
    
    params = {}
    if "?" in clean:
        clean, param_str = clean.split("?", 1)
        for pair in param_str.split("&"):
            if "=" in pair:
                k, v = pair.split("=", 1)
                params[k] = v

    auth = ""
    host_port_db = clean
    if "@" in clean:
        auth, host_port_db = clean.split("@", 1)

    user = ""
    password = ""
    if auth:
        if ":" in auth:
            user, password = auth.split(":", 1)
        else:
            user = auth

    database = "postgres"
    host_port = host_port_db
    if "/" in host_port_db:
        host_port, database = host_port_db.split("/", 1)
        database = database or "postgres"

    port = 5432
    host = host_port
    if ":" in host_port:
        host, port_str = host_port.split(":", 1)
        try:
            port = int(port_str)
        except ValueError:
            return None

    if not host or not user or not validate_port(port):
        return None

    return {
        "user": user,
        "password": password,
        "host": host,
        "port": port,
        "database": database,
        "sslmode": params.get("sslmode", "require")
    }


class TestValidationUtils(unittest.TestCase):
    def test_domain_validation(self):
        self.assertTrue(validate_domain("automation.example.com"))
        self.assertTrue(validate_domain("n8n.workflow.io"))
        self.assertTrue(validate_domain("sub.domain.co.uk"))
        self.assertFalse(validate_domain("http://example.com"))
        self.assertFalse(validate_domain("https://example.com/path"))
        self.assertFalse(validate_domain("example.com:5678"))
        self.assertFalse(validate_domain("-bad.domain.com"))
        self.assertFalse(validate_domain(""))

    def test_email_validation(self):
        self.assertTrue(validate_email("admin@example.com"))
        self.assertTrue(validate_email("devops.alerts+aws@company.org"))
        self.assertFalse(validate_email("plainaddress"))
        self.assertFalse(validate_email("@missingusername.com"))
        self.assertFalse(validate_email("user@.com"))

    def test_ipv4_validation(self):
        self.assertTrue(validate_ipv4("1.2.3.4"))
        self.assertTrue(validate_ipv4("192.168.1.1"))
        self.assertTrue(validate_ipv4("54.210.123.45"))
        self.assertFalse(validate_ipv4("256.1.1.1"))
        self.assertFalse(validate_ipv4("1.2.3"))
        self.assertFalse(validate_ipv4("1.2.3.4.5"))
        self.assertFalse(validate_ipv4("abc.def.ghi.jkl"))

    def test_port_validation(self):
        self.assertTrue(validate_port(80))
        self.assertTrue(validate_port(443))
        self.assertTrue(validate_port("5678"))
        self.assertTrue(validate_port(65535))
        self.assertFalse(validate_port(0))
        self.assertFalse(validate_port(70000))
        self.assertFalse(validate_port("-1"))
        self.assertFalse(validate_port("abc"))

    def test_postgres_uri_parsing(self):
        uri1 = "postgresql://postgres.myproject:secretpassword123@aws-0-us-east-1.pooler.supabase.com:5432/postgres?sslmode=require"
        p1 = parse_postgres_uri(uri1)
        self.assertIsNotNone(p1)
        self.assertEqual(p1["user"], "postgres.myproject")
        self.assertEqual(p1["password"], "secretpassword123")
        self.assertEqual(p1["host"], "aws-0-us-east-1.pooler.supabase.com")
        self.assertEqual(p1["port"], 5432)
        self.assertEqual(p1["database"], "postgres")
        self.assertEqual(p1["sslmode"], "require")

        uri2 = "postgres://n8n_user:pass456@db.example.org:5433/n8n_db"
        p2 = parse_postgres_uri(uri2)
        self.assertIsNotNone(p2)
        self.assertEqual(p2["port"], 5433)
        self.assertEqual(p2["database"], "n8n_db")

        # Invalid scheme
        self.assertIsNone(parse_postgres_uri("mysql://user:pass@host:3306/db"))
        # Invalid port
        self.assertIsNone(parse_postgres_uri("postgresql://user:pass@host:99999/db"))

if __name__ == "__main__":
    unittest.main()
