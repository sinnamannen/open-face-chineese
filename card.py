import random
import pygame
import numpy as np
import sys
pygame.font.init()

from global_variables import *

class Card:
    def __init__(self, suit, value):
        self.suit = suit
        self.value = value
        
        self.suit_colour = self.get_colour()
        self.suit_unicode = self.get_unicode()
        self.clicked = False
        self.clicked_previous = False
        self.width = 100
        self.height = 200
        self.x = None
        self.y = None
    
    def card_str(self):
        return f"{self.value}{self.suit}"
    
    def get_colour(self):
        return (255, 0, 0) if self.suit in ["❤️", "♦️"] else (0, 0, 0)
    
    def get_unicode(self):
        if self.suit == "❤️": return u'\u2665'
        elif self.suit == "♦️": return u'\u2666'
        elif self.suit == "♣️": return u'\u2663'
        else: return u'\u2660'
    
    def gets_clicked(self, pokerwindow):
        if pokerwindow.mouse_get_pressed == True and self.x <= pokerwindow.mouse_position[0] <= self.x + self.width and self.y <= pokerwindow.mouse_position[1] <= self.x + self.height:
            pokerwindow.holding_card.append(self)
    
    def gets_unclicked(self, pokerwindow, xy):
        pokerwindow.holding_card.append(self)
        
        if xy[0] > pokerwindow.screen_width // 2:
            if xy[1] < pokerwindow.screen_height // 3 : play = 1
            elif xy[1] < pokerwindow.screen_height * 2 // 3: play = 2
            else: play = 3
            
            if play < 3 and len(pokerwindow.players[0].board[play-1]) < 5:
                pokerwindow.players[0].play_card(self, play)  
            if play == 3 and len(pokerwindow.players[0].board[play-1]) < 3:
                pokerwindow.players[0].play_card(self, play)  

    def set_coordinate(self, x, y):
        self.x = x
        self.y = y
    
    def blit(self, screen):
        pygame.draw.rect(screen, (255,255,255), (self.x, self.y, self.width, self.height))
        screen.blit(pygame.font.Font(None, 150).render(self.value, True, self.suit_colour), (self.x + self.width // 8, self.y + self.height // 16))
        screen.blit(pygame.font.Font(pygame.font.match_font('Arial'), 150).render(self.suit_unicode, True, self.suit_colour),(self.x + self.width // 16, self.y + self.height // 4))