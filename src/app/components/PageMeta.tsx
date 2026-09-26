import {useEffect} from 'react';

const SITE = 'Verse';

function metaDescription() {
  let tag = document.querySelector<HTMLMetaElement>('meta[name="description"]');
  if (!tag) {
    tag = document.createElement('meta');
    tag.name = 'description';
    document.head.appendChild(tag);
  }
  return tag;
}

/**
 * Gives a page its own document title and meta description (the SPA otherwise
 * shares the index.html defaults on every route) and restores them on unmount.
 */
export function usePageMeta(title?: string, description?: string) {
  useEffect(() => {
    if (!title) return;
    const previousTitle = document.title;
    const tag = metaDescription();
    const previousDescription = tag.content;
    document.title = title.includes(SITE) ? title : `${title} · ${SITE}`;
    if (description) tag.content = description.length > 160 ? `${description.slice(0, 157).trimEnd()}…` : description;
    return () => {
      document.title = previousTitle;
      tag.content = previousDescription;
    };
  }, [title, description]);
}
