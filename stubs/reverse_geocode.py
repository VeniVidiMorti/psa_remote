"""Stand-in for reverse_geocode, which needs numpy and scipy.

psa_car_controller imports it in ecomix.py, but only uses it to look up the country for CO2 data, which this app does not use.
"""


def search(coordinates):
    raise NotImplementedError("reverse_geocode is not available in this app")
