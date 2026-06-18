@tool
extends Node

var model
var custom_model_text
var api_key = "AIzaSyArTBrAO7x8GGlhhHr9w_9VvdDdgEo78b4"
var allow_multiline
var chat_history: Array = [ 
]

signal completion_received(completion, pre, post)
signal chat_received(text)
signal completion_error(error)

#Make an add function

#Expects return value of String Array
func _get_models():
	return []

#Expects return value of String Array
func _clean_chat():
	print_rich("[b]_clean_chat[/b] - Deleting chat history")
	chat_history = []

#Sets active model
func _set_model(model_name):
	print_rich("[b]_set_model[/b] - Setted model: ", model_name)
	model = model_name


func _set_custom_model_text(text):
	custom_model_text = text

#Sets API key
func _set_api_key(key):
	print_rich("[b]_set_api_key[/b] - Setted apiKey: ", key)
	api_key = key

#Determines if multiline completions are allowed
func _set_multiline(allowed):
	allow_multiline = allowed

#Sends user prompt
func _send_user_prompt(user_prompt, user_suffix):
	pass
