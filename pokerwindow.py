import random
import pygame
import numpy as np
import sys
pygame.font.init()

from player import Player
from card import Card
from deck import Deck
from global_variables import *

class PokerWindow:
    def __init__(self, screen_width = 1400, screen_height = 800):
        self.players = []
        self.deck = Deck()
        self.deck.shuffle()
        self.screen_width = screen_width
        self.screen_height = screen_height
        self.screen = pygame.display.set_mode((screen_width, screen_height))
        self.background_color = (0, 128, 255)
        
        self.running = True
        self.mouse_position = np.array([0,0])
        self.mouse_position_prev = np.array([0,0])
        self.mouse_get_pressed = False
        self.mouse_get_pressed_prev = False
        self.first_round = True
        self.full_board = False
        self.holding_card = []
    
    def add_player(self, name):
        self.players.append(Player(name))
        
    def get_mouse_change(self):
        return self.mouse_position - self.mouse_position_prev
    
    def get_values_list(self, hand):
        return [card.value for card in hand]
    
    def get_suits_list(self, hand):
        return [card.suit for card in hand]
    
    def restart(self):
        self.deck = Deck()
        self.deck.shuffle()
        
        for player in self.players:
            player.empty_hand()
            player.empty_board()
            player.draw_cards(5, self.deck)
            player.points = 0
            player.total_points = 0

        self.mouse_get_pressed = False
        self.mouse_get_pressed_prev = False
        self.first_round = True
        self.full_board = False
        self.holding_card = []
        
    def play(self):         
        
        pygame.display.set_caption("Open faced chineese poker") 
        
        for player in self.players:
            player.draw_cards(5, self.deck)
        
        while self.running:
            
            if pygame.key.get_pressed()[pygame.K_r]:
                self.restart()
            
            self.mouse_get_pressed = False
            self.mouse_position = np.array(pygame.mouse.get_pos())
            
            if len(self.players[0].hand) == 0 and self.full_board == False:
                self.players[0].draw_cards(ncards=3, deck = self.deck)
                self.first_round = False
            
            if len(self.players[0].hand) == 1 and self.first_round == False and self.full_board == False:
                self.players[0].empty_hand()
                if sum([len(i) for i in self.players[0].board]) == 13:
                    self.full_board = True
                    
                    score1 = score(self.get_values_list(self.players[0].board[0]), self.get_suits_list(self.players[0].board[0]))
                    score2 = score(self.get_values_list(self.players[0].board[1]), self.get_suits_list(self.players[0].board[1]))
                    score3 = score_front(self.get_values_list(self.players[0].board[2]))
                    self.players[0].edit_points([score1, score2, score3[0]])
                    
                else: 
                    self.players[0].draw_cards(ncards=3, deck = self.deck)
            
############ Events and things to do between each frame
            
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                if event.type == pygame.MOUSEBUTTONDOWN:
                    self.mouse_get_pressed = True
            
            if self.mouse_get_pressed:
                if self.mouse_get_pressed_prev == False and  len(self.holding_card) == 0:
                    for card in self.players[0].hand:
                        card.gets_clicked(self)
                elif self.mouse_get_pressed_prev == False and  len(self.holding_card) > 0:
                    self.holding_card[0].gets_unclicked(self, self.mouse_position)
                    self.holding_card = []
            
            #For quick input to the board
            if len(self.holding_card) > 0 and pygame.key.get_pressed()[pygame.K_1]:
                self.holding_card[0].gets_unclicked(self,[1000, 100])
                self.holding_card = []
            elif len(self.holding_card) > 0 and pygame.key.get_pressed()[pygame.K_2]:
                self.holding_card[0].gets_unclicked(self,[1000, 400])
                self.holding_card = []
            elif len(self.holding_card) > 0 and pygame.key.get_pressed()[pygame.K_3]:
                self.holding_card[0].gets_unclicked(self,[1000, 800])
                self.holding_card = []
                    
            
            for card in self.holding_card:
                card.set_coordinate(card.x + self.get_mouse_change()[0], card.y + self.get_mouse_change()[1])
                
############
                
                    
###################VISUAL STUFF, must be calcuated earlier

            # Fill the screen with the background color
            self.screen.fill(self.background_color)
 
            self.players[0].blit_hand(50,50,self.screen)
            self.players[0].blit_board(800,50,self.screen)
            
            if self.full_board:
                self.screen.blit(pygame.font.Font(None, 150).render(score1, True, (0,255,0)), (50, 50))
                self.screen.blit(pygame.font.Font(None, 150).render(score2, True, (0,255,0)), (50, 325))
                self.screen.blit(pygame.font.Font(None, 150).render(score3[1], True, (0,255,0)), (50, 600))
                self.screen.blit(pygame.font.Font(None, 150).render(str(self.players[0].points), True, (0,255,0)), (1200, 600))
                

            # Update the display
            pygame.display.flip()
            
#####################
            
            self.mouse_position_prev = self.mouse_position.copy()
            self.mouse_get_pressed_prev = self.mouse_get_pressed

        # Quit pygame
        pygame.quit()
        sys.exit()         