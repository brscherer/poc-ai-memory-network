import unittest

from shop.cart import Cart


class CartTest(unittest.TestCase):
    def test_add_accumulates_quantity(self):
        cart = Cart()
        cart.add("mug")
        cart.add("mug", 2)
        self.assertEqual(cart.lines, {"mug": 3})

    def test_unknown_sku_is_rejected(self):
        with self.assertRaises(KeyError):
            Cart().add("nope")


if __name__ == "__main__":
    unittest.main()
