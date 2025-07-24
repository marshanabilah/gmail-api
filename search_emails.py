import os
import base64
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from google_apis import create_service

def init_gmail_service(client_file, api_name='gmail', api_version='v1', scopes=['https://mail.google.com/']):
    """
    Initializes the Gmail API service.
    """
    return create_service(client_file, api_name, api_version, scopes)

def _extract_body(payload):
    body = '<Text body not available>'
    if 'parts' in payload:
        for part in payload['parts']:
            if part['mimeType'] == 'multipart/alternative':
                for subpart in part['parts']:
                    if subpart['mimeType'] == 'text/plain' and 'data' in subpart['body']:
                        body = base64.urlsafe_b64decode(subpart['body']['data']).decode('utf-8')
                        break
            elif part['mimeType'] == 'text/plain' and 'data' in part['body']:
                body = base64.urlsafe_b64decode(part['body']['data']).decode('utf-8')
                break
    elif 'body' in payload and 'data' in payload['body']:
        body = base64.urlsafe_b64decode(payload['body']['data']).decode('utf-8')
    return body

def get_email_message(service, user_id='me', label_ids=None, folder_name='INBOX', max_results=5):
    messages = []
    next_page_token = None

    if folder_name:
        label_results = service.users().labels().list(userId=user_id).execute()
        labels = label_results.get('labels', [])
        folder_label_id = next((label['id'] for label in labels if label['name'].lower() == folder_name.lower()), None)
        if folder_label_id:
            if label_ids:
                label_ids.append(folder_label_id)
            else:
                label_ids = [folder_label_id]
        else:
            raise ValueError(f"Folder '{folder_name}' not found in labels.")
        
    while True:
        result = service.users().messages().list(
            userId=user_id,
            labelIds=label_ids,
            pageToken=next_page_token,
            maxResults=min(500, max_results - len(messages) if max_results else 500)
        ).execute()

        messages.extend(result.get('messages', []))
        next_page_token = result.get('nextPageToken')

        if not next_page_token or (max_results and len(messages) >= max_results):
            break

    return messages

def search_emails(service, query, user_id='me', max_results=5):
    """
    Searches for emails matching the given query.
    
    :param service: The Gmail API service instance.
    :param query: The search query string.
    :param user_id: The user's email address or 'me' for the authenticated user.
    :param label_ids: List of label IDs to filter the search results.
    :param folder_name: The name of the folder to search in (default is 'INBOX').
    :param max_results: Maximum number of results to return.
    :return: List of email messages matching the query.
    """
    messages = []
    next_page_token = None

    while True:
        result = service.users().messages().list(
            userId=user_id,
            q=query,
            pageToken=next_page_token,
            maxResults=min(500, max_results - len(messages) if max_results else 500)
        ).execute()

        messages.extend(result.get('messages', []))
        next_page_token = result.get('nextPageToken')

        if not next_page_token or (max_results and len(messages) >= max_results):
            break
    
    return messages[:max_results] if max_results else messages


def search_email_conversations(service, query, user_id='me', max_results=5):
    """
    Searches for email conversations matching the given query.
    
    :param service: The Gmail API service instance.
    :param query: The search query string.
    :param user_id: The user's email address or 'me' for the authenticated user.
    :param max_results: Maximum number of results to return.
    :return: List of email conversations matching the query.
    """
    conversations = []
    next_page_token = None

    while True:
        result = service.users().threads().list(
            userId=user_id,
            q=query,
            pageToken=next_page_token,
            maxResults=min(500, max_results - len(conversations) if max_results else 500)
        ).execute()

        conversations.extend(result.get('threads', []))
        next_page_token = result.get('nextPageToken')

        if not next_page_token or (max_results and len(conversations) >= max_results):
            break
    
    return conversations[:max_results] if max_results else conversations