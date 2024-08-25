import random
import pygame
import numpy as np
import sys

pygame.font.init()

from card import Card
from deck import Deck
from global_variables import *

class Player:
    def __init__(self, name):
        self.hand = []
        self.board = [[],[],[]]
        self.name = name
        self.points = 0
        self.total_points = 0
        
    def draw_cards(self, ncards, deck):
        cards_drawn = deck.deck_list[:ncards]
        self.hand.extend(cards_drawn)
        deck.deck_list[:] = deck.deck_list[ncards:]
        
        """
        sette x og y koordinater for oppe til venstre hjørnet til kortene
        """
        for i, card in enumerate(cards_drawn):
            card.set_coordinate(100 + int(i * card.width * 11 / 10), 100)
        
    def play_card(self, card, play):
        card_index = self.hand.index(card)
        self.board[play - 1].append(self.hand[card_index])
        self.hand.pop(card_index)
    
    def empty_hand(self):
        self.hand = []
    
    def empty_board(self):
        self.board = [[],[],[]]
        
####### For printing
    def hand_str(self):
        hand_str_ = ""
        for card in self.hand:
            hand_str_ += f"{card.card_str()} "
        return hand_str_
    
    def print_hand(self):
        print( self.hand_str() )
        
    def board_str(self):
        board_str_ = ""
        for row in self.board:
            for card in row:
                board_str_ += f"{card.card_str()} "
            board_str_ += "\n"
        
        return board_str_
    
    def print_board(self):
        print( self.board_str() )
############

    def blit_hand(self, x, y, screen):
        for card in self.hand:
            card.blit(screen)
        
        
    def blit_board(self, x, y, screen):
        for j, row in enumerate(self.board):
            for i, card in enumerate(row):
                card.set_coordinate(x + int(i*card.width*11/10), y + int(j*card.height*5/4))
                card.blit(screen)

    def edit_points(self, scores):
        points1 = points_dict[scores[0]][0] if scores[0] in points_dict else 0
        points2 = points_dict[scores[1]][1] if scores[1] in points_dict else 0
        points3 = points_dict_front[scores[2]] if scores[2] in points_dict_front else 0
        
        self.points = points1 + points2 + points3
         
    
    def edid_total_points(self):
        return