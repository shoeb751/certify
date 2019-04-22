use yui;
CREATE table IF NOT EXISTS ssl_certs (
	id INT AUTO_INCREMENT,
    name text,
    last_change timestamp,
    expires timestamp,
    subject text,
    issuer text,
    raw text,
    fingerprint text,
    modulus_sha1 text,
    PRIMARY KEY (id)
);

CREATE table IF NOT EXISTS ssl_keys (
	id INT AUTO_INCREMENT,
    name text,
    last_change timestamp,
    raw text,
    modulus_sha1 text,
    PRIMARY KEY (id)
);