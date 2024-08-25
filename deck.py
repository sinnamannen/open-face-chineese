import random
import pygame
import numpy as np
import sys
pygame.font.init()

from card import Card
from global_variables import *

class Deck:
    def __init__(self):
        self.deck_list = []
        for suit in suits:
            for value in values:
                self.deck_list.append(Card(suit, value))
                
    def deck_str(self):
        deck_str_ = ""
        for card in self.deck_list:
            deck_str_ += f"{card.card_str()} "
        return deck_str_
    
    def display_deck(self):
        print(self.deck_str())
        
    def shuffle(self):
        random.shuffle(self.deck_list)